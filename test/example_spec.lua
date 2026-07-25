-- test/example_spec.lua
-- Example test file for smart-ime.nvim

local lu = require('luaunit')

TestSmartIme = {}

function TestSmartIme:setUp()
    -- Reload the module before each test
    package.loaded['smart-ime'] = nil
end

function TestSmartIme:test_module_loads()
    local smart_ime = require('smart-ime')
    lu.assertNotNil(smart_ime)
    lu.assertIsFunction(smart_ime.setup)
end

function TestSmartIme:test_setup_accepts_options()
    local smart_ime = require('smart-ime')
    local ok, err = pcall(smart_ime.setup, {
        imselect = 'echo',
        save_on = { 'InsertLeave' },
        restore_on = { 'InsertEnter' },
        normalize_on = { 'FocusGained' },
        enable_log = false,
    })
    lu.assertTrue(ok, 'setup() should not error: ' .. tostring(err))
end

function TestSmartIme:test_setup_with_defaults()
    local smart_ime = require('smart-ime')
    local ok, err = pcall(smart_ime.setup, {
        imselect = 'echo',
        enable_log = false,
    })
    lu.assertTrue(ok, 'setup() should work with minimal options: ' .. tostring(err))
end

return TestSmartIme

