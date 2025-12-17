local M = {}

local default_opt = {
    save_on = { 'InsertLeave' },
    restore_on = { 'InsertEnter' },
    normalize_on = { 'FocusGained' },
    enable_log = true,
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

    local create_autocmd = vim.api.nvim_create_autocmd

    local imselect = opt.imselect

    local function imselect_cn()
        vim.system({ imselect, '-k=ctrl+space', '中文模式' })
    end

    local function imselect_en()
        vim.system({ imselect, '-k=ctrl+space', '英语模式' })
    end

    local buffer_im = {}

    create_autocmd(opt.save_on, {
        pattern = { '*' },
        group = augroup,
        callback = function(ev)
            vim.system({ imselect }, { text = true }, function(o)
                -- 这里说明下，再 Windows Terminal 内执行该命令输出的内容默认编码是 `cp936`,
                -- 需要转码成 utf-8，同时，输出内容尾部有换行符，使用 trim 函数去除。
                local m = vim.trim(vim.iconv(o.stdout, 'cp936', 'utf-8'))
                info('save buffer insert mode: ' .. m)
                buffer_im[ev.buf] = m
            end)
            imselect_en()
        end,
    })
    create_autocmd(opt.restore_on, {
        pattern = { '*' },
        group = augroup,
        callback = function(ev)
            if buffer_im[ev.buf] and buffer_im[ev.buf] ~= '英语模式' then
                -- 此处设置快捷键，可以在输入法按键设置里面查看，我选择的是使用 ctrl-space 切换中英文
                -- 默认我记得是 shift，同时这个命令默认也是 `-k=shift`
                info('change to ' .. buffer_im[ev.buf])
                vim.system({ imselect, '-k=ctrl+space', buffer_im[ev.buf] })
            end
        end,
    })

    create_autocmd(opt.normalize_on, {
        pattern = { '*' },
        group = augroup,
        callback = function(ev)
            info(string.format('%s event is triggered', ev.event))
            if vim.fn.mode() == 'n' then
                info('switch to english in normal mode')
                imselect_en()
            elseif vim.fn.mode() == 'i' then
                if buffer_im[ev.buf] == '英语模式' then
                    info('switch to english in insert mode')
                    imselect_en()
                elseif buffer_im[ev.buf] == '中文模式' then
                    info('switch to chinese in insert mode')
                    imselect_cn()
                end
            end
        end,
    })
end

return M
