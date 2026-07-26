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

    ---Query current IME state via PowerShell (synchronous, blocks ~200-500ms)
    ---Uses ImmGetDefaultIMEWnd + SendMessage(WM_IME_CONTROL, IMC_GETCONVERSIONMODE)
    ---to query the actual IME conversion status of the foreground window.
    ---@return string|nil '中文模式', '英语模式', or nil if query fails
    local function query_im_state()
        local ps_script = [[
try {
    $sig = '[DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow(); [DllImport("user32.dll")] public static extern IntPtr SendMessage(IntPtr hWnd, uint Msg, IntPtr wParam, IntPtr lParam); [DllImport("imm32.dll")] public static extern IntPtr ImmGetDefaultIMEWnd(IntPtr hWnd);'
    Add-Type -MemberDefinition $sig -Name 'IMEQ' -Namespace 'IME'
    $hwnd = [IME.IMEQ]::GetForegroundWindow()
    $hIme = [IME.IMEQ]::ImmGetDefaultIMEWnd($hwnd)
    if ($hIme -eq [IntPtr]::Zero) { 'unknown' } else {
        $mode = [int][IME.IMEQ]::SendMessage($hIme, 0x0283, [IntPtr]1, [IntPtr]0)
        if ($mode -band 1) { 'chinese' } else { 'english' }
    }
} catch { 'unknown' }
]]

        local result = vim.system({ 'powershell.exe', '-NoProfile', '-Command', ps_script }, {}):wait()
        if result.code == 0 then
            local output = vim.trim(result.stdout or '')
            if output == 'chinese' then
                return '中文模式'
            elseif output == 'english' then
                return '英语模式'
            end
        end
        return nil
    end

    ---Switch IME using PowerShell keybd_event API
    ---Sends the key combination directly at the system level.
    ---@param target string target mode (for logging only)
    local function powershell_switch(target)
        info('powershell_switch: ' .. target .. ', key: ' .. switch_key)

        local keys = parse_key_to_vk(switch_key)
        if #keys == 0 then
            warn('failed to parse switch_key: ' .. switch_key)
            return
        end

        -- Build PowerShell script using keybd_event
        local ps_parts = {
            "$sig = '[DllImport(\"user32.dll\")] public static extern void keybd_event(byte bVk, byte bScan, uint dwFlags, System.UIntPtr dwExtraInfo);'",
            "Add-Type -MemberDefinition $sig -Name 'KB' -Namespace 'IME'",
        }

        -- Key down events (dwFlags=0)
        for _, vk in ipairs(keys) do
            table.insert(ps_parts, string.format('[IME.KB]::keybd_event(0x%02X, 0, 0, [System.UIntPtr]::Zero)', vk))
        end
        -- Key up events in reverse order (dwFlags=2 = KEYEVENTF_KEYUP)
        for i = #keys, 1, -1 do
            table.insert(ps_parts, string.format('[IME.KB]::keybd_event(0x%02X, 0, 2, [System.UIntPtr]::Zero)', keys[i]))
        end

        local ps_cmd = table.concat(ps_parts, '; ')
        vim.system({ 'powershell.exe', '-NoProfile', '-Command', ps_cmd })
    end

    ---Switch to English, querying actual IME state first to avoid redundant toggles.
    ---@param queried_state string|nil pre-queried state to avoid duplicate query
    local function switch_to_en(queried_state)
        local state = queried_state or query_im_state()
        if state then
            current_im = state
        end

        if state == '英语模式' then
            info('already in english (queried), skip toggle')
            return
        end
        if state == nil and current_im == '英语模式' then
            info('query failed, current_im says english, skip toggle')
            return
        end

        powershell_switch('英语模式')
        current_im = '英语模式'
    end

    ---Switch to Chinese, querying actual IME state first to avoid redundant toggles.
    ---@param queried_state string|nil pre-queried state to avoid duplicate query
    local function switch_to_cn(queried_state)
        local state = queried_state or query_im_state()
        if state then
            current_im = state
        end

        if state == '中文模式' then
            info('already in chinese (queried), skip toggle')
            return
        end
        if state == nil and current_im == '中文模式' then
            info('query failed, current_im says chinese, skip toggle')
            return
        end

        powershell_switch('中文模式')
        current_im = '中文模式'
    end

    local buffer_im = {}

    create_autocmd(opt.save_on, {
        pattern = { '*' },
        group = augroup,
        callback = function(ev)
            info(string.format('InsertLeave triggered, buf=%d, event=%s', ev.buf, ev.event))

            -- Query actual IME state and save for this buffer
            local state = query_im_state()
            if state then
                current_im = state
            end
            buffer_im[ev.buf] = state or current_im or '中文模式'
            info('buffer_im[' .. ev.buf .. '] = ' .. tostring(buffer_im[ev.buf]))

            info('switch to english on InsertLeave')
            switch_to_en(state)
        end,
    })

    create_autocmd(opt.restore_on, {
        pattern = { '*' },
        group = augroup,
        callback = function(ev)
            info(string.format('InsertEnter triggered, buf=%d', ev.buf))
            info('buffer_im[' .. ev.buf .. '] = ' .. tostring(buffer_im[ev.buf]))

            if buffer_im[ev.buf] and buffer_im[ev.buf] ~= '' and buffer_im[ev.buf] ~= '英语模式' then
                info('change to ' .. buffer_im[ev.buf])
                switch_to_cn()
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
            vim.defer_fn(function()
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
                    switch_to_en()
                elseif mode == 'i' then
                    if buffer_im[buf] == '英语模式' then
                        info('switch to english in insert mode')
                        switch_to_en()
                    elseif buffer_im[buf] == '中文模式' then
                        info('switch to chinese in insert mode')
                        switch_to_cn()
                    end
                end
            end, opt.delay)
        end,
    })
end

return M

