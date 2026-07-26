local M = {}

local default_opt = {
    save_on = { 'InsertLeave' },
    restore_on = { 'InsertEnter' },
    normalize_on = { 'FocusGained' },
    enable_log = true,
    delay = 100,
    ---@type string IME toggle key, e.g. "ctrl+space", "shift"
    switch_key = 'ctrl+space',
}

local log

function M.setup(opt)
    opt = vim.tbl_deep_extend('force', default_opt, opt or {})
    local augroup = vim.api.nvim_create_augroup('smart-ime.nvim', { clear = true })

    if opt.enable_log then
        pcall(function()
            log = require('logger').derive('smart-ime')
        end)
    end
    local function info(msg)
        if log and opt.enable_log then
            log.info(msg)
        end
    end

    local function warn(msg)
        if log and opt.enable_log then
            log.warn(msg)
        end
    end

    local create_autocmd = vim.api.nvim_create_autocmd
    local switch_key = opt.switch_key

    info('switch_key: ' .. switch_key)

    -- Fallback state tracking (used when query fails)
    local current_im = nil

    ---@diagnostic disable-next-line: lowercase-global
    ---Epoch counter for async race condition prevention.
    ---Each event handler increments epoch and captures its value.
    ---Async callbacks check if their captured epoch is still current;
    ---if not, they are discarded (a newer event has superseded them).
    local epoch = 0

    ---Increment epoch and return the new value.
    ---Call at the start of every event handler to invalidate stale callbacks.
    local function new_epoch()
        epoch = epoch + 1
        return epoch
    end

    ---Parse key string into VK codes for keybd_event
    ---@param key_str string e.g. "ctrl+space", "shift"
    ---@return table array of VK codes
    local function parse_key_to_vk(key_str)
        local vk_map = {
            ctrl = 0x11,
            shift = 0x10,
            alt = 0x12,
            space = 0x20,
            win = 0x5B,
        }
        local parts = vim.split(key_str, '+')
        local keys = {}
        for _, part in ipairs(parts) do
            part = vim.trim(part):lower()
            local vk = vk_map[part]
            if vk then
                table.insert(keys, vk)
            elseif part:match('^0x[0-9a-fA-F]+$') then
                table.insert(keys, tonumber(part:sub(3), 16))
            end
        end
        return keys
    end

    ---Build keybd_event PowerShell commands from VK codes
    ---@param keys table array of VK codes
    ---@return string PowerShell expression string
    local function build_key_events(keys)
        local cmds = {}
        for _, vk in ipairs(keys) do
            table.insert(cmds, string.format('[SmartIME.IME]::keybd_event(0x%02X, 0, 0, [System.UIntPtr]::Zero)', vk))
        end
        for i = #keys, 1, -1 do
            table.insert(cmds, string.format('[SmartIME.IME]::keybd_event(0x%02X, 0, 2, [System.UIntPtr]::Zero)', keys[i]))
        end
        return table.concat(cmds, '; ')
    end

    ---Merged query + conditional toggle in a single PowerShell process.
    ---Queries IME state, outputs the BEFORE state, and toggles if needed.
    ---Latency: ~200-500ms (one process) instead of ~400-1000ms (two sequential).
    ---
    ---Script output:
    ---   'chinese'  — was Chinese (toggled to English if target was 'english')
    ---   'english'  — was English (toggled to Chinese if target was 'chinese')
    ---   'unknown'  — query failed (no toggle performed)
    ---
    ---@param target string 'english' or 'chinese'
    ---@param callback fun(before_state: string|nil) receives the BEFORE state
    ---@param is_valid fun(): boolean|nil epoch validator
    local function smart_switch(target, callback, is_valid)
        local keys = parse_key_to_vk(switch_key)
        if #keys == 0 then
            warn('failed to parse switch_key: ' .. switch_key)
            return
        end

        local key_events = build_key_events(keys)

        local ps_script = string.format([[
$target = '%s'
try {
    $sig = '[DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow(); [DllImport("user32.dll")] public static extern IntPtr SendMessage(IntPtr hWnd, uint Msg, IntPtr wParam, IntPtr lParam); [DllImport("imm32.dll")] public static extern IntPtr ImmGetDefaultIMEWnd(IntPtr hWnd); [DllImport("user32.dll")] public static extern void keybd_event(byte bVk, byte bScan, uint dwFlags, System.UIntPtr dwExtraInfo);'
    Add-Type -MemberDefinition $sig -Name 'IME' -Namespace 'SmartIME'
    $hwnd = [SmartIME.IME]::GetForegroundWindow()
    $hIme = [SmartIME.IME]::ImmGetDefaultIMEWnd($hwnd)
    if ($hIme -eq [IntPtr]::Zero) { 'unknown' } else {
        $mode = [int][SmartIME.IME]::SendMessage($hIme, 0x0283, [IntPtr]1, [IntPtr]0)
        if ($mode -band 1) {
            'chinese'
            if ($target -eq 'english') { %s }
        } else {
            'english'
            if ($target -eq 'chinese') { %s }
        }
    }
} catch { 'unknown' }
]], target, key_events, key_events)

        info('smart_switch: target=' .. target .. ', key=' .. switch_key)

        vim.system({ 'powershell.exe', '-NoProfile', '-Command', ps_script }, {}, function(result)
            if is_valid and not is_valid() then
                return
            end

            local before_state = nil
            if result.code == 0 then
                local output = vim.trim(result.stdout or '')
                if output == 'chinese' then
                    before_state = '中文模式'
                elseif output == 'english' then
                    before_state = '英语模式'
                end
            end

            callback(before_state)
        end)
    end

    ---Blind toggle via PowerShell keybd_event (fire-and-forget, no query).
    ---Used as fallback when smart_switch's query fails.
    ---@param target_state string '英语模式' or '中文模式' (for logging)
    local function powershell_switch(target_state)
        info('powershell_switch (fallback): ' .. target_state .. ', key: ' .. switch_key)

        local keys = parse_key_to_vk(switch_key)
        if #keys == 0 then
            warn('failed to parse switch_key: ' .. switch_key)
            return
        end

        local key_events = build_key_events(keys)
        local ps_script = string.format([[
$sig = '[DllImport("user32.dll")] public static extern void keybd_event(byte bVk, byte bScan, uint dwFlags, System.UIntPtr dwExtraInfo);'
Add-Type -MemberDefinition $sig -Name 'IME' -Namespace 'SmartIME'
%s
]], key_events)

        vim.system({ 'powershell.exe', '-NoProfile', '-Command', ps_script })
    end

    ---Process smart_switch result: update current_im, fallback blind toggle on failure.
    ---@param target string 'english' or 'chinese'
    ---@param before_state string|nil state before toggle, or nil if query failed
    local function apply_switch_result(target, before_state)
        local target_state = target == 'english' and '英语模式' or '中文模式'
        if before_state then
            -- Query succeeded: script already toggled (or skipped if already in target)
            current_im = target_state
        elseif current_im ~= target_state then
            -- Query failed: blind toggle as fallback
            powershell_switch(target_state)
            current_im = target_state
        end
    end

    local buffer_im = {}

    create_autocmd(opt.save_on, {
        pattern = { '*' },
        group = augroup,
        callback = function(ev)
            info(string.format('InsertLeave triggered, buf=%d, event=%s', ev.buf, ev.event))

            local ep = new_epoch()
            local is_valid = function()
                return epoch == ep
            end

            -- Early save: best-guess before async query completes.
            -- Ensures InsertEnter (if it fires immediately after) can read a
            -- reasonable value from buffer_im instead of stale data.
            buffer_im[ev.buf] = current_im or '中文模式'

            -- Merged query + toggle in a single PowerShell process (async)
            smart_switch('english', function(before_state)
                if not is_valid() then
                    info('InsertLeave callback discarded (superseded by newer event)')
                    return
                end

                apply_switch_result('english', before_state)
                if before_state then
                    buffer_im[ev.buf] = before_state
                end
                info('buffer_im[' .. ev.buf .. '] = ' .. tostring(buffer_im[ev.buf]))
            end, is_valid)
        end,
    })

    create_autocmd(opt.restore_on, {
        pattern = { '*' },
        group = augroup,
        callback = function(ev)
            info(string.format('InsertEnter triggered, buf=%d', ev.buf))
            info('buffer_im[' .. ev.buf .. '] = ' .. tostring(buffer_im[ev.buf]))

            local ep = new_epoch()
            local is_valid = function()
                return epoch == ep
            end

            if buffer_im[ev.buf] and buffer_im[ev.buf] ~= '' and buffer_im[ev.buf] ~= '英语模式' then
                info('change to ' .. buffer_im[ev.buf])
                smart_switch('chinese', function(before_state)
                    if not is_valid() then
                        info('InsertEnter callback discarded (superseded by newer event)')
                        return
                    end
                    apply_switch_result('chinese', before_state)
                end, is_valid)
            else
                info('no need to switch, buffer_im is empty or already english')
            end
        end,
    })

    create_autocmd(opt.normalize_on, {
        pattern = { '*' },
        group = augroup,
        callback = function(ev)
            local buf = ev.buf
            local event = ev.event
            info(string.format('%s event is triggered, buf=%d', event, buf))

            local ep = new_epoch()
            local is_valid = function()
                return epoch == ep
            end

            vim.defer_fn(function()
                if not is_valid() then
                    info(string.format('%s deferred handler discarded (superseded)', event))
                    return
                end

                local mode = vim.fn.mode()
                info(string.format(
                    'deferred %s handler: mode=%s, buffer_im[%d]=%s',
                    event,
                    mode,
                    buf,
                    tostring(buffer_im[buf])
                ))
                if mode == 'n' then
                    info('switch to english in normal mode')
                    smart_switch('english', function(before_state)
                        if not is_valid() then
                            return
                        end
                        apply_switch_result('english', before_state)
                    end, is_valid)
                elseif mode == 'i' then
                    if buffer_im[buf] == '英语模式' then
                        info('switch to english in insert mode')
                        smart_switch('english', function(before_state)
                            if not is_valid() then
                                return
                            end
                            apply_switch_result('english', before_state)
                        end, is_valid)
                    elseif buffer_im[buf] == '中文模式' then
                        info('switch to chinese in insert mode')
                        smart_switch('chinese', function(before_state)
                            if not is_valid() then
                                return
                            end
                            apply_switch_result('chinese', before_state)
                        end, is_valid)
                    end
                end
            end, opt.delay)
        end,
    })
end

return M

