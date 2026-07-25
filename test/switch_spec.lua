-- test/switch_spec.lua
-- Tests for IME switching behavior (InsertLeave, InsertEnter, FocusGained)

local lu = require('luaunit')

TestSwitch = {}

-- ---------------------------------------------------------------------------
-- Mock infrastructure
-- ---------------------------------------------------------------------------

local system_calls        -- captures vim.system calls (switch commands)
local fn_system_calls     -- captures vim.fn.system calls (query commands)
local original_system
local original_fn_system
local original_tempname
local original_readfile
local original_delete
local mock_stdout

local function setup_mock(stdout)
    mock_stdout = stdout or ''
    system_calls = {}
    fn_system_calls = {}

    original_system = vim.system
    original_fn_system = vim.fn.system
    original_tempname = vim.fn.tempname
    original_readfile = vim.fn.readfile
    original_delete = vim.fn.delete

    -- Mock vim.system for switch commands (imselect_switch and powershell_switch)
    ---@diagnostic disable-next-line: duplicate-set-field
    vim.system = function(cmd, opts, on_exit)
        table.insert(system_calls, { cmd = cmd, opts = opts })

        local result = { stdout = '', stderr = '', code = 0 }
        local obj = { wait = function()
            return result
        end }

        if on_exit then
            vim.schedule(function()
                on_exit(result)
            end)
        end

        return obj
    end

    -- Mock vim.fn.system for query commands
    ---@diagnostic disable-next-line: duplicate-set-field
    vim.fn.system = function(cmd)
        table.insert(fn_system_calls, cmd)
        return ''
    end

    -- Mock vim.fn.tempname
    vim.fn.tempname = function()
        return '/tmp/mock-imselect-output'
    end

    -- Mock vim.fn.readfile to return mock_stdout as lines
    vim.fn.readfile = function(_path)
        if mock_stdout == '' then
            return {}
        end
        return vim.split(mock_stdout, '\n')
    end

    -- Mock vim.fn.delete as no-op
    vim.fn.delete = function(_path)
        return 0
    end
end

local function teardown_mock()
    if original_system then
        vim.system = original_system
        original_system = nil
    end
    if original_fn_system then
        vim.fn.system = original_fn_system
        original_fn_system = nil
    end
    if original_tempname then
        vim.fn.tempname = original_tempname
        original_tempname = nil
    end
    if original_readfile then
        vim.fn.readfile = original_readfile
        original_readfile = nil
    end
    if original_delete then
        vim.fn.delete = original_delete
        original_delete = nil
    end
end

--- Find a vim.system call whose cmd array contains ALL given args.
local function find_call(...)
    local args = { ... }
    for _, call in ipairs(system_calls) do
        local match = true
        for _, arg in ipairs(args) do
            local found = false
            for _, cmd_arg in ipairs(call.cmd) do
                if cmd_arg == arg then
                    found = true
                    break
                end
            end
            if not found then
                match = false
                break
            end
        end
        if match then
            return call
        end
    end
    return nil
end

--- Find a vim.system call that looks like a PowerShell switch.
local function find_powershell_call()
    for _, call in ipairs(system_calls) do
        if call.cmd[1] == 'powershell.exe' then
            return call
        end
    end
    return nil
end

--- Find any vim.system call that is an imselect switch (contains target mode).
local function find_switch_call(target)
    return find_call(target)
end

-- ---------------------------------------------------------------------------
-- Setup / teardown
-- ---------------------------------------------------------------------------

function TestSwitch:setUp()
    package.loaded['smart-ime'] = nil
    vim.cmd('enew!')
end

function TestSwitch:tearDown()
    teardown_mock()
end

-- ---------------------------------------------------------------------------
-- engine = 'powershell' tests
-- ---------------------------------------------------------------------------

function TestSwitch:test_powershell_engine_skips_imselect_query()
    setup_mock('')

    local smart_ime = require('smart-ime')
    smart_ime.setup({
        engine = 'powershell',
        enable_log = false,
    })

    vim.api.nvim_exec_autocmds('InsertLeave', { pattern = '*' })

    lu.assertEquals(#fn_system_calls, 0, 'should not query imselect at all')
end

function TestSwitch:test_powershell_engine_uses_powershell_switch()
    setup_mock('')

    local smart_ime = require('smart-ime')
    smart_ime.setup({
        engine = 'powershell',
        enable_log = false,
    })

    vim.api.nvim_exec_autocmds('InsertLeave', { pattern = '*' })

    lu.assertNotNil(find_powershell_call(), 'should use PowerShell for switching')
    lu.assertNil(find_switch_call('英语模式'), 'should not call imselect for switching')
end

function TestSwitch:test_powershell_engine_works_without_imselect_config()
    setup_mock('')

    local smart_ime = require('smart-ime')
    smart_ime.setup({
        engine = 'powershell',
        enable_log = false,
        -- no imselect config
    })

    vim.api.nvim_exec_autocmds('InsertLeave', { pattern = '*' })

    lu.assertNotNil(find_powershell_call(), 'should work without imselect config')
end

function TestSwitch:test_powershell_engine_restores_chinese_on_insertenter()
    setup_mock('')

    local smart_ime = require('smart-ime')
    smart_ime.setup({
        engine = 'powershell',
        enable_log = false,
    })

    -- InsertLeave: assumes Chinese, switches to English via PowerShell
    vim.api.nvim_exec_autocmds('InsertLeave', { pattern = '*' })

    system_calls = {}

    -- InsertEnter: should restore Chinese via PowerShell
    vim.api.nvim_exec_autocmds('InsertEnter', { pattern = '*' })

    lu.assertNotNil(find_powershell_call(), 'should use PowerShell to restore Chinese')
end

function TestSwitch:test_powershell_engine_uses_custom_switch_key()
    setup_mock('')

    local smart_ime = require('smart-ime')
    smart_ime.setup({
        engine = 'powershell',
        switch_key = 'shift',
        enable_log = false,
    })

    vim.api.nvim_exec_autocmds('InsertLeave', { pattern = '*' })

    local ps_call = find_powershell_call()
    lu.assertNotNil(ps_call, 'should use PowerShell')
    lu.assertNotNil(string.find(ps_call.cmd[4], '0x10'), 'should use shift VK code (0x10)')
end

-- ---------------------------------------------------------------------------
-- InsertLeave tests (engine = 'auto')
-- ---------------------------------------------------------------------------

function TestSwitch:test_insert_leave_switches_to_english_with_detection()
    setup_mock('中文模式\n')

    local smart_ime = require('smart-ime')
    smart_ime.setup({
        imselect = 'mock-imselect',
        enable_log = false,
    })

    vim.api.nvim_exec_autocmds('InsertLeave', { pattern = '*' })

    lu.assertNotNil(find_switch_call('英语模式'), 'should switch to English on InsertLeave')
end

function TestSwitch:test_insert_leave_switches_to_english_without_detection()
    setup_mock('')

    local smart_ime = require('smart-ime')
    smart_ime.setup({
        imselect = 'mock-imselect',
        enable_log = false,
    })

    vim.api.nvim_exec_autocmds('InsertLeave', { pattern = '*' })

    -- When detection fails, should fall back to PowerShell
    lu.assertNotNil(find_powershell_call(), 'should use PowerShell fallback when detection fails')
end

function TestSwitch:test_insert_leave_queries_current_state()
    setup_mock('中文模式\n')

    local smart_ime = require('smart-ime')
    smart_ime.setup({
        imselect = 'mock-imselect',
        enable_log = false,
    })

    vim.api.nvim_exec_autocmds('InsertLeave', { pattern = '*' })

    lu.assertTrue(#fn_system_calls > 0, 'should query current IME state via vim.fn.system')
    lu.assertNotNil(string.find(fn_system_calls[1], 'mock-imselect', 1, true),
        'query command should contain imselect path')
end

function TestSwitch:test_insert_leave_switch_command_has_correct_args()
    setup_mock('中文模式\n')

    local smart_ime = require('smart-ime')
    smart_ime.setup({
        imselect = 'mock-imselect',
        enable_log = false,
    })

    vim.api.nvim_exec_autocmds('InsertLeave', { pattern = '*' })

    local en_call = find_switch_call('英语模式')
    lu.assertNotNil(en_call, 'should have English switch call')
    lu.assertEquals(en_call.cmd[1], 'mock-imselect')
    lu.assertEquals(en_call.cmd[2], '-k=ctrl+space')
    lu.assertEquals(en_call.cmd[3], '英语模式')
end

function TestSwitch:test_insert_leave_saves_chinese_state()
    setup_mock('中文模式\n')

    local smart_ime = require('smart-ime')
    smart_ime.setup({
        imselect = 'mock-imselect',
        enable_log = false,
    })

    -- InsertLeave saves state and switches to English
    vim.api.nvim_exec_autocmds('InsertLeave', { pattern = '*' })

    -- Clear calls to isolate InsertEnter
    system_calls = {}

    -- InsertEnter should restore Chinese
    vim.api.nvim_exec_autocmds('InsertEnter', { pattern = '*' })

    lu.assertNotNil(find_switch_call('中文模式'),
        'should restore Chinese on InsertEnter after saving Chinese state')
end

-- ---------------------------------------------------------------------------
-- InsertEnter tests (engine = 'auto')
-- ---------------------------------------------------------------------------

function TestSwitch:test_insert_enter_no_switch_when_english()
    setup_mock('英语模式\n')

    local smart_ime = require('smart-ime')
    smart_ime.setup({
        imselect = 'mock-imselect',
        enable_log = false,
    })

    -- InsertLeave saves English state
    vim.api.nvim_exec_autocmds('InsertLeave', { pattern = '*' })

    -- Clear calls
    system_calls = {}

    -- InsertEnter should NOT switch (already English)
    vim.api.nvim_exec_autocmds('InsertEnter', { pattern = '*' })

    lu.assertNil(find_switch_call('中文模式'), 'should not switch to Chinese when saved state is English')
    lu.assertNil(find_switch_call('英语模式'), 'should not switch at all when saved state is English')
end

function TestSwitch:test_insert_enter_no_switch_without_saved_state()
    setup_mock('')

    local smart_ime = require('smart-ime')
    smart_ime.setup({
        imselect = 'mock-imselect',
        enable_log = false,
    })

    -- Trigger InsertEnter directly (no prior InsertLeave to save state)
    vim.api.nvim_exec_autocmds('InsertEnter', { pattern = '*' })

    lu.assertNil(find_switch_call('中文模式'), 'should not switch to Chinese without saved state')
    lu.assertNil(find_switch_call('英语模式'), 'should not switch to English on InsertEnter')
end

-- ---------------------------------------------------------------------------
-- Empty output keeps previous state (key bug fix)
-- ---------------------------------------------------------------------------

function TestSwitch:test_empty_output_keeps_previous_state()
    setup_mock('中文模式\n')

    local smart_ime = require('smart-ime')
    smart_ime.setup({
        imselect = 'mock-imselect',
        enable_log = false,
    })

    -- First InsertLeave: detects and saves Chinese state
    vim.api.nvim_exec_autocmds('InsertLeave', { pattern = '*' })

    -- Simulate detection failure (empty output)
    mock_stdout = ''

    -- Second InsertLeave: detection fails, should keep previous Chinese state
    vim.api.nvim_exec_autocmds('InsertLeave', { pattern = '*' })

    -- Clear calls
    system_calls = {}

    -- InsertEnter should still restore Chinese
    -- After query failure, switch_works=false, so it uses PowerShell
    vim.api.nvim_exec_autocmds('InsertEnter', { pattern = '*' })

    lu.assertNotNil(find_powershell_call(),
        'should use PowerShell to restore Chinese even after detection failure')
end

-- ---------------------------------------------------------------------------
-- FocusGained tests
-- ---------------------------------------------------------------------------

function TestSwitch:test_focus_gained_normal_mode_switches_to_english()
    setup_mock('')

    local smart_ime = require('smart-ime')
    smart_ime.setup({
        imselect = 'mock-imselect',
        enable_log = false,
        delay = 0,
    })

    -- Ensure normal mode
    vim.cmd('stopinsert')

    vim.api.nvim_exec_autocmds('FocusGained', { pattern = '*' })

    -- Wait for deferred function to execute
    local ok = vim.wait(1000, function()
        return #system_calls > 0
    end, 10)

    lu.assertTrue(ok, 'deferred FocusGained handler should execute within timeout')
    -- After query failure on InsertLeave, switch_works=false, uses PowerShell
    -- But if no InsertLeave happened yet, switch_works is still true
    lu.assertTrue(find_switch_call('英语模式') ~= nil or find_powershell_call() ~= nil,
        'should switch to English on FocusGained in normal mode')
end

function TestSwitch:test_focus_gained_normal_mode_switches_to_english_with_chinese_state()
    setup_mock('中文模式\n')

    local smart_ime = require('smart-ime')
    smart_ime.setup({
        imselect = 'mock-imselect',
        enable_log = false,
        delay = 0,
    })

    -- Save Chinese state via InsertLeave
    vim.api.nvim_exec_autocmds('InsertLeave', { pattern = '*' })

    -- Clear calls
    system_calls = {}

    -- Ensure normal mode
    vim.cmd('stopinsert')

    -- FocusGained in normal mode should switch to English even with Chinese state
    vim.api.nvim_exec_autocmds('FocusGained', { pattern = '*' })

    local ok = vim.wait(1000, function()
        return #system_calls > 0
    end, 10)

    lu.assertTrue(ok, 'deferred FocusGained handler should execute within timeout')
    lu.assertTrue(find_switch_call('英语模式') ~= nil or find_powershell_call() ~= nil,
        'should switch to English on FocusGained in normal mode')
    lu.assertNil(find_switch_call('中文模式'), 'should not switch to Chinese in normal mode')
end

return TestSwitch

