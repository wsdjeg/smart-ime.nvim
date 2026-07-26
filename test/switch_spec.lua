-- test/switch_spec.lua
-- Tests for IME switching behavior (InsertLeave, InsertEnter, FocusGained)

local lu = require('luaunit')

TestSwitch = {}

-- ---------------------------------------------------------------------------
-- Mock infrastructure
-- ---------------------------------------------------------------------------

local system_calls
local original_system
local mock_im_state

local function setup_mock()
    system_calls = {}
    mock_im_state = nil
    original_system = vim.system

    ---@diagnostic disable-next-line: duplicate-set-field
    vim.system = function(cmd, opts, on_exit)
        local cmd_str = table.concat(cmd, ' ')
        local is_query = string.find(cmd_str, 'GetForegroundWindow') ~= nil

        if is_query then
            -- Query call: return mock state, don't record in system_calls
            local result = { stdout = mock_im_state or 'unknown', stderr = '', code = 0 }
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

        -- Toggle call: record it
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
end

local function teardown_mock()
    if original_system then
        vim.system = original_system
        original_system = nil
    end
end

local function set_mock_im_state(state)
    mock_im_state = state
end

--- Find a vim.system call that is a PowerShell toggle (not a query).
local function find_powershell_call()
    for _, call in ipairs(system_calls) do
        if call.cmd[1] == 'powershell.exe' then
            return call
        end
    end
    return nil
end

--- Find all PowerShell toggle calls (not queries).
local function find_all_powershell_calls()
    local calls = {}
    for _, call in ipairs(system_calls) do
        if call.cmd[1] == 'powershell.exe' then
            table.insert(calls, call)
        end
    end
    return calls
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

function TestSwitch:test_insert_leave_switches_to_english()
    setup_mock()

    local smart_ime = require('smart-ime')
    smart_ime.setup({ enable_log = false })

    vim.api.nvim_exec_autocmds('InsertLeave', { pattern = '*' })

    lu.assertNotNil(find_powershell_call(), 'should use PowerShell on InsertLeave')
end

function TestSwitch:test_insert_leave_saves_chinese_state()
    setup_mock()

    local smart_ime = require('smart-ime')
    smart_ime.setup({ enable_log = false })

    -- InsertLeave saves state and switches to English
    vim.api.nvim_exec_autocmds('InsertLeave', { pattern = '*' })

    system_calls = {}

    -- InsertEnter should restore Chinese
    vim.api.nvim_exec_autocmds('InsertEnter', { pattern = '*' })

    lu.assertNotNil(find_powershell_call(), 'should restore Chinese on InsertEnter')
end

-- ---------------------------------------------------------------------------
-- InsertEnter tests
-- ---------------------------------------------------------------------------

function TestSwitch:test_insert_enter_no_switch_without_saved_state()
    setup_mock()

    local smart_ime = require('smart-ime')
    smart_ime.setup({ enable_log = false })

    -- Trigger InsertEnter directly (no prior InsertLeave)
    vim.api.nvim_exec_autocmds('InsertEnter', { pattern = '*' })

    lu.assertNil(find_powershell_call(), 'should not switch without saved state')
end

function TestSwitch:test_insert_enter_restores_after_insert_leave()
    setup_mock()

    local smart_ime = require('smart-ime')
    smart_ime.setup({ enable_log = false })

    -- First InsertLeave: assumes Chinese, switches to English
    vim.api.nvim_exec_autocmds('InsertLeave', { pattern = '*' })

    system_calls = {}

    -- InsertEnter: should switch to Chinese
    vim.api.nvim_exec_autocmds('InsertEnter', { pattern = '*' })

    lu.assertNotNil(find_powershell_call(), 'should use PowerShell to restore Chinese')
end

-- ---------------------------------------------------------------------------
-- Redundant toggle prevention tests (query-based)
-- ---------------------------------------------------------------------------

function TestSwitch:test_insert_leave_skips_toggle_when_already_english()
    setup_mock()
    set_mock_im_state('english')

    local smart_ime = require('smart-ime')
    smart_ime.setup({ enable_log = false })

    -- Query says already English, should NOT toggle
    vim.api.nvim_exec_autocmds('InsertLeave', { pattern = '*' })

    lu.assertNil(find_powershell_call(), 'should not toggle when query says already English')
end

function TestSwitch:test_insert_leave_toggles_when_query_says_chinese()
    setup_mock()
    set_mock_im_state('chinese')

    local smart_ime = require('smart-ime')
    smart_ime.setup({ enable_log = false })

    -- Query says Chinese, should toggle to English
    vim.api.nvim_exec_autocmds('InsertLeave', { pattern = '*' })

    lu.assertNotNil(find_powershell_call(), 'should toggle when query says Chinese')
end

function TestSwitch:test_insert_enter_skips_toggle_when_already_chinese()
    setup_mock()
    set_mock_im_state('chinese')

    local smart_ime = require('smart-ime')
    smart_ime.setup({ enable_log = false })

    -- InsertLeave: query says Chinese, toggles to English
    -- Set mock to English after InsertLeave to simulate the toggle effect
    vim.api.nvim_exec_autocmds('InsertLeave', { pattern = '*' })
    set_mock_im_state('english')

    system_calls = {}

    -- InsertEnter: buffer_im says Chinese, but query says already Chinese
    -- Wait - after InsertLeave toggled to English, mock says English now
    -- InsertEnter should restore Chinese
    set_mock_im_state('english') -- IM is English after InsertLeave toggle
    vim.api.nvim_exec_autocmds('InsertEnter', { pattern = '*' })

    -- Should toggle to Chinese
    lu.assertNotNil(find_powershell_call(), 'should toggle to Chinese on InsertEnter')
end

function TestSwitch:test_insert_enter_skips_when_query_says_already_chinese()
    setup_mock()
    set_mock_im_state('chinese')

    local smart_ime = require('smart-ime')
    smart_ime.setup({ enable_log = false })

    -- InsertLeave with Chinese state: toggles to English
    vim.api.nvim_exec_autocmds('InsertLeave', { pattern = '*' })

    -- Now mock that IM is already Chinese (e.g. user manually toggled)
    set_mock_im_state('chinese')

    system_calls = {}

    -- InsertEnter: buffer_im says Chinese, but query also says Chinese -> skip
    vim.api.nvim_exec_autocmds('InsertEnter', { pattern = '*' })

    lu.assertNil(find_powershell_call(), 'should not toggle when query says already Chinese')
end

-- ---------------------------------------------------------------------------
-- Fallback tests (query fails, use current_im)
-- ---------------------------------------------------------------------------

function TestSwitch:test_fallback_when_query_fails()
    setup_mock()
    -- mock_im_state is nil, so query returns 'unknown' -> nil

    local smart_ime = require('smart-ime')
    smart_ime.setup({ enable_log = false })

    -- First InsertLeave: query fails, current_im is nil -> toggle
    vim.api.nvim_exec_autocmds('InsertLeave', { pattern = '*' })
    lu.assertNotNil(find_powershell_call(), 'should toggle on first InsertLeave when query fails')

    system_calls = {}

    -- Second InsertLeave: query fails, current_im = '英语模式' -> skip
    vim.api.nvim_exec_autocmds('InsertLeave', { pattern = '*' })
    lu.assertNil(find_powershell_call(), 'should skip toggle when current_im says English')
end

-- ---------------------------------------------------------------------------
-- Picker scenario test (the bug fix)
-- ---------------------------------------------------------------------------

function TestSwitch:test_picker_scenario_no_double_toggle()
    setup_mock()

    local smart_ime = require('smart-ime')
    smart_ime.setup({ enable_log = false })

    -- 1. User in original buffer insert mode (Chinese), leaves insert -> English
    local orig_buf = vim.api.nvim_get_current_buf()
    vim.api.nvim_exec_autocmds('InsertLeave', { pattern = '*' })

    -- 2. Picker opens in a DIFFERENT buffer, InsertEnter -> no saved state, no switch
    local picker_buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_set_current_buf(picker_buf)
    vim.api.nvim_exec_autocmds('InsertEnter', { pattern = '*' })

    system_calls = {}

    -- 3. Picker closes, InsertLeave fires for original buffer
    --    IM is already English (picker didn't change it), should NOT toggle
    vim.api.nvim_set_current_buf(orig_buf)
    vim.api.nvim_exec_autocmds('InsertLeave', { pattern = '*' })

    lu.assertNil(find_powershell_call(), 'should not toggle when IM is already English after picker')
end

-- ---------------------------------------------------------------------------
-- Custom switch_key tests
-- ---------------------------------------------------------------------------

function TestSwitch:test_custom_switch_key_shift()
    setup_mock()

    local smart_ime = require('smart-ime')
    smart_ime.setup({
        switch_key = 'shift',
        enable_log = false,
    })

    vim.api.nvim_exec_autocmds('InsertLeave', { pattern = '*' })

    local ps_call = find_powershell_call()
    lu.assertNotNil(ps_call, 'should use PowerShell')
    lu.assertNotNil(string.find(ps_call.cmd[4], '0x10'), 'should use shift VK code (0x10)')
end

function TestSwitch:test_custom_switch_key_ctrl_space()
    setup_mock()

    local smart_ime = require('smart-ime')
    smart_ime.setup({
        switch_key = 'ctrl+space',
        enable_log = false,
    })

    vim.api.nvim_exec_autocmds('InsertLeave', { pattern = '*' })

    local ps_call = find_powershell_call()
    lu.assertNotNil(ps_call, 'should use PowerShell')
    lu.assertNotNil(string.find(ps_call.cmd[4], '0x11'), 'should contain ctrl VK code (0x11)')
    lu.assertNotNil(string.find(ps_call.cmd[4], '0x20'), 'should contain space VK code (0x20)')
end

-- ---------------------------------------------------------------------------
-- FocusGained tests
-- ---------------------------------------------------------------------------

function TestSwitch:test_focus_gained_normal_mode_switches_to_english()
    setup_mock()

    local smart_ime = require('smart-ime')
    smart_ime.setup({
        enable_log = false,
        delay = 0,
    })

    vim.cmd('stopinsert')

    vim.api.nvim_exec_autocmds('FocusGained', { pattern = '*' })

    local ok = vim.wait(1000, function()
        return #system_calls > 0
    end, 10)

    lu.assertTrue(ok, 'deferred FocusGained handler should execute within timeout')
    lu.assertNotNil(find_powershell_call(), 'should switch to English on FocusGained in normal mode')
end

function TestSwitch:test_focus_gained_normalizes_to_english_after_chinese()
    setup_mock()

    local smart_ime = require('smart-ime')
    smart_ime.setup({
        enable_log = false,
        delay = 0,
    })

    -- InsertLeave -> English, InsertEnter -> Chinese
    vim.api.nvim_exec_autocmds('InsertLeave', { pattern = '*' })
    vim.api.nvim_exec_autocmds('InsertEnter', { pattern = '*' })

    system_calls = {}

    -- FocusGained in normal mode: should switch back to English
    vim.cmd('stopinsert')
    vim.api.nvim_exec_autocmds('FocusGained', { pattern = '*' })

    local ok = vim.wait(1000, function()
        return #system_calls > 0
    end, 10)

    lu.assertTrue(ok, 'deferred FocusGained handler should execute within timeout')
    lu.assertNotNil(find_powershell_call(), 'should switch to English on FocusGained after Chinese')
end

function TestSwitch:test_focus_gained_normal_mode_skips_when_already_english()
    setup_mock()
    set_mock_im_state('english')

    local smart_ime = require('smart-ime')
    smart_ime.setup({
        enable_log = false,
        delay = 0,
    })

    -- InsertLeave: query says English, no toggle
    vim.api.nvim_exec_autocmds('InsertLeave', { pattern = '*' })

    system_calls = {}

    vim.cmd('stopinsert')
    vim.api.nvim_exec_autocmds('FocusGained', { pattern = '*' })

    -- Wait a bit for deferred handler
    vim.wait(200, function()
        return #system_calls > 0
    end, 10)

    -- Query says English, should NOT toggle
    local calls = find_all_powershell_calls()
    lu.assertEquals(#calls, 0, 'should not toggle when query says already English')
end

return TestSwitch

