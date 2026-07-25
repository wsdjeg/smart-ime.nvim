local M = {}

local default_opt = {
    save_on = { 'InsertLeave' },
    restore_on = { 'InsertEnter' },
    normalize_on = { 'FocusGained' },
    enable_log = true,
    delay = 100,
    ---@type 'auto'|'powershell'|'imselect'
    engine = 'auto',
    ---@type string IME toggle key, e.g. "ctrl+space", "shift"
    switch_key = 'ctrl+space',
    ---@type string? path to im-select tool (not needed for engine='powershell')
    imselect = nil,
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

    local engine = opt.engine
    local switch_key = opt.switch_key
    local imselect = opt.imselect and vim.fn.expand(opt.imselect) or nil

    info('engine: ' .. engine .. ', switch_key: ' .. switch_key)
    if imselect then
        info('imselect path: ' .. imselect)
    end

    -- Validate config
    if engine ~= 'powershell' and (not imselect or imselect == '') then
        warn('imselect is not configured, falling back to engine=powershell')
        engine = 'powershell'
    end

    -- State flags
    local query_works = (engine == 'auto' or engine == 'imselect')
    local switch_works = (engine == 'auto' or engine == 'imselect')

    if engine == 'powershell' then
        info('using powershell engine, skipping imselect entirely')
    end

    ---Run imselect query via cmd.exe redirect to file
    ---@return string output
    local function imselect_query()
        local tmpfile = vim.fn.tempname()
        local cmd_str = string.format('"%s" -v > "%s" 2>&1', imselect, tmpfile)
        info('executing query via file redirect: ' .. cmd_str)

        vim.fn.system(cmd_str)
        local lines = vim.fn.readfile(tmpfile)
        vim.fn.delete(tmpfile)

        local output = table.concat(lines or {}, '\n')
        info('query output (len=' .. #output .. '): ' .. output)

        return output
    end

    ---Parse imselect verbose output to extract current IME mode
    ---@param output string
    ---@return string mode
    local function parse_mode(output)
        if not output or output == '' then
            return ''
        end
        local lines = vim.split(output, '\n')
        for i = #lines, 1, -1 do
            local line = vim.trim(lines[i])
            if line ~= '' and line:match('模式$') then
                return line
            end
        end
        return ''
    end

    ---Switch IME using im-select tool
    ---@param target string target mode (中文模式 or 英语模式)
    local function imselect_switch(target)
        info('imselect_switch: ' .. target .. ', key: ' .. switch_key)
        vim.system({ imselect, '-k=' .. switch_key, target })
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
        info('powershell command: ' .. ps_cmd)
        vim.system({ 'powershell.exe', '-NoProfile', '-Command', ps_cmd })
    end

    ---Switch to English IME
    local function switch_to_en()
        if switch_works then
            imselect_switch('英语模式')
        else
            powershell_switch('英语模式')
        end
    end

    ---Switch to Chinese IME
    local function switch_to_cn()
        if switch_works then
            imselect_switch('中文模式')
        else
            powershell_switch('中文模式')
        end
    end

    local buffer_im = {}

    create_autocmd(opt.save_on, {
        pattern = { '*' },
        group = augroup,
        callback = function(ev)
            info(string.format('InsertLeave triggered, buf=%d, event=%s', ev.buf, ev.event))
            info('current buffer_im state: ' .. vim.inspect(buffer_im))

            if query_works then
                local output = imselect_query()
                local mode = parse_mode(output)

                info('parsed mode: "' .. mode .. '" (len=' .. #mode .. ')')

                if mode == '' then
                    warn('imselect query returned empty mode, falling back to manual tracking')
                    warn('imselect raw output: ' .. output)
                    query_works = false
                    switch_works = false
                    warn('switching to PowerShell keybd_event fallback for IME switching')
                else
                    info('save buffer insert mode: ' .. mode)
                    buffer_im[ev.buf] = mode
                    info('buffer_im[' .. ev.buf .. '] = ' .. buffer_im[ev.buf])
                end
            else
                -- Query doesn't work, track state manually
                if not buffer_im[ev.buf] then
                    buffer_im[ev.buf] = '中文模式'
                    info('query unavailable, assuming buffer_im[' .. ev.buf .. '] = 中文模式')
                end
            end

            info('switch to english on InsertLeave')
            switch_to_en()
        end,
    })

    create_autocmd(opt.restore_on, {
        pattern = { '*' },
        group = augroup,
        callback = function(ev)
            info(string.format('InsertEnter triggered, buf=%d', ev.buf))
            info('buffer_im[' .. ev.buf .. '] = ' .. tostring(buffer_im[ev.buf]))
            info('current buffer_im state: ' .. vim.inspect(buffer_im))

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
            info('buffer_im[' .. buf .. '] = ' .. tostring(buffer_im[buf]))
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
                    else
                        info('insert mode but buffer_im is not english or chinese: ' .. tostring(buffer_im[buf]))
                    end
                else
                    info('mode is not n or i: ' .. mode .. ', no action')
                end
            end, opt.delay)
        end,
    })
end

return M

