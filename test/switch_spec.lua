-- test/switch_spec.lua
-- Tests for IME switching behavior (InsertLeave, InsertEnter, FocusGained)

local lu = require('luaunit')

TestSwitch = {}

-- ---------------------------------------------------------------------------
-- Mock infrastructure: capture vim.system calls and mock vim.iconv
-- ---------------------------------------------------------------------------

local system_calls
local original_system
local original_iconv
local mock_stdout

local function setup_mock(stdout)
    mock_stdout = stdout or ''
    system_calls = {}
    original_system = vim.system
    original_iconv = vim.iconv

    ---@diagnostic disable-next-line: duplicate-set-field
    vim.system = function(cmd, opts, on_exit)
        table.insert(system_calls, { cmd = cmd, opts = opts })

        local result = {
            stdout = mock_stdout,
            stderr = '',
            code = 0,
        }

        local obj = {
            wait = function()
                return result
            end,
        }

        if on_exit then
            vim.schedule(function()
                on_exit(result)
            end)
        end

        return obj
    end

    ---@diagnostic disable-next-line: duplicate-set-field
    vim.iconv = function(s, from, to)
        return s
    end
end

local function teardown_mock()
    if original_system then
        vim.system = original_system
        original_system = nil
    end
    if original_iconv then
        vim.iconv = original_iconv
        original_iconv = nil
    end
end

--- Find a system call whose cmd array contains ALL given args.
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

--- Find the query call (imselect with no extra args).
local function find_query_call(imselect)
    for _, call in ipairs(system_calls) do
        if #call.cmd == 1 and call.cmd[1] == imselect then
            return call
        end
    end
    return nil
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
-- InsertLeave tests
-- ---------------------------------------------------------------------------

function TestSwitch:test_insert_leave_switches_to_english_with_detection()
    setup_mock('中文模式\n')

    local smart_ime = require('smart-ime')
    smart_ime.setup({
        imselect = 'mock-imselect',
        enable_log = false,
    })

    vim.api.nvim_exec_autocmds('InsertLeave', { pattern = '*' })

    lu.assertNotNil(find_call('英语模式'), 'should switch to English on InsertLeave')
end

function TestSwitch:test_insert_leave_switches_to_english_without_detection()
    setup_mock('')

    local smart_ime = require('smart-ime')
    smart_ime.setup({
        imselect = 'mock-imselect',
        enable_log = false,
    })

    vim.api.nvim_exec_autocmds('InsertLeave', { pattern = '*' })

    lu.assertNotNil(find_call('英语模式'), 'should switch to English even when detection returns empty')
end

function TestSwitch:test_insert_leave_queries_current_state()
    setup_mock('中文模式\n')

    local smart_ime = require('smart-ime')
    smart_ime.setup({
        imselect = 'mock-imselect',
        enable_log = false,
    })

    vim.api.nvim_exec_autocmds('InsertLeave', { pattern = '*' })

    lu.assertNotNil(find_query_call('mock-imselect'), 'should query current IME state')
end

function TestSwitch:test_insert_leave_switch_command_has_correct_args()
    setup_mock('中文模式\n')

    local smart_ime = require('smart-ime')
    smart_ime.setup({
        imselect = 'mock-imselect',
        enable_log = false,
    })

    vim.api.nvim_exec_autocmds('InsertLeave', { pattern = '*' })

    local en_call = find_call('英语模式')
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

    lu.assertNotNil(find_call('中文模式'), 'should restore Chinese on InsertEnter after saving Chinese state')
end

-- ---------------------------------------------------------------------------
-- InsertEnter tests
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

    lu.assertNil(find_call('中文模式'), 'should not switch to Chinese when saved state is English')
    lu.assertNil(find_call('英语模式'), 'should not switch at all when saved state is English')
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

    lu.assertNil(find_call('中文模式'), 'should not switch to Chinese without saved state')
    lu.assertNil(find_call('英语模式'), 'should not switch to English on InsertEnter')
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

    -- InsertEnter should still restore Chinese (state was preserved)
    vim.api.nvim_exec_autocmds('InsertEnter', { pattern = '*' })

    lu.assertNotNil(find_call('中文模式'), 'should restore Chinese even after detection failure')
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
        return find_call('英语模式') ~= nil
    end, 10)

    lu.assertTrue(ok, 'deferred FocusGained handler should execute within timeout')
    lu.assertNotNil(find_call('英语模式'), 'should switch to English on FocusGained in normal mode')
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
        return find_call('英语模式') ~= nil
    end, 10)

    lu.assertTrue(ok, 'deferred FocusGained handler should execute within timeout')
    lu.assertNotNil(find_call('英语模式'), 'should switch to English on FocusGained in normal mode')
    lu.assertNil(find_call('中文模式'), 'should not switch to Chinese in normal mode')
end

return TestSwitch

