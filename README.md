# smart-ime.nvim

Smart per-buffer IME switching for Neovim on Windows.

[![Run Tests](https://github.com/wsdjeg/smart-ime.nvim/actions/workflows/test.yml/badge.svg)](https://github.com/wsdjeg/smart-ime.nvim/actions/workflows/test.yml)
[![GitHub License](https://img.shields.io/github/license/wsdjeg/smart-ime.nvim)](LICENSE)
[![GitHub Issues or Pull Requests](https://img.shields.io/github/issues/wsdjeg/smart-ime.nvim)](https://github.com/wsdjeg/smart-ime.nvim/issues)
[![GitHub commit activity](https://img.shields.io/github/commit-activity/m/wsdjeg/smart-ime.nvim)](https://github.com/wsdjeg/smart-ime.nvim/commits/master/)
[![GitHub Release](https://img.shields.io/github/v/release/wsdjeg/smart-ime.nvim)](https://github.com/wsdjeg/smart-ime.nvim/releases)
[![luarocks](https://img.shields.io/luarocks/v/wsdjeg/smart-ime.nvim)](https://luarocks.org/modules/wsdjeg/smart-ime.nvim)

## Requirements

- **Neovim** 0.10+
- **Windows** with PowerShell available (`powershell.exe` in PATH)
- Your IME toggle key configured in Windows (e.g. `Ctrl+Space`)

No external binaries required. The plugin uses the Windows `keybd_event` API
through PowerShell to simulate keystrokes.

## How it works

The plugin **simulates your IME toggle key** (e.g. `Ctrl+Space`) to switch
between English and Chinese input. It does not query the current IME state —
instead, it tracks state per buffer manually:

1. **`InsertLeave`** — Saves the buffer's IME state (defaults to Chinese on
   first leave), then toggles to English so normal-mode commands are safe.
2. **`InsertEnter`** — If the saved state was Chinese, toggles back to Chinese.
3. **`FocusGained`** — After a short delay, normalizes IME based on current
   mode: English in normal mode, saved state in insert mode.

> **Note:** Since switching relies on the toggle key, the `switch_key` option
> must match your actual Windows IME toggle key. If you manually change IME
> outside Neovim, the tracked state may become out of sync.

## Features

- **Per-buffer IME state** — Each buffer remembers its own input method state.
- **Automatic switching** — English on `InsertLeave`, restore on `InsertEnter`.
- **Focus normalization** — Ensures consistent IME state when Neovim regains focus.
- **Zero dependencies** — No `im-select` or other external binaries needed.
- **Async & non-blocking** — Uses `vim.system()` for all PowerShell calls.
- **Optional logging** — Integrates with [logger.nvim](https://github.com/wsdjeg/logger.nvim) when available.
- **No background polling** — Reacts only to editor events.

## Installation

<details open>
<summary>lazy.nvim</summary>

```lua
{
    'wsdjeg/smart-ime.nvim',
    opts = {},
}
```

</details>

<details>
<summary>nvim-plug</summary>

```lua
return {
    'wsdjeg/smart-ime.nvim',
    opts = {},
}
```

</details>

<details>
<summary>Manual</summary>

```lua
-- After cloning to your runtimepath:
require('smart-ime').setup({})
```

</details>

## Configuration

### Defaults

```lua
{
    switch_key = 'ctrl+space',       -- IME toggle key
    save_on = { 'InsertLeave' },     -- Events to save IME state
    restore_on = { 'InsertEnter' },  -- Events to restore IME state
    normalize_on = { 'FocusGained' }, -- Events to normalize IME state
    delay = 100,                     -- Delay (ms) for deferred normalization
    enable_log = true,               -- Enable logging via logger.nvim
}
```

### Options

| Option         | Type       | Default              | Description                                              |
| -------------- | ---------- | -------------------- | -------------------------------------------------------- |
| `switch_key`   | `string`   | `'ctrl+space'`       | IME toggle key, must match your Windows IME setting      |
| `save_on`      | `string[]` | `{ 'InsertLeave' }`  | Autocmd events that trigger save + switch to English     |
| `restore_on`   | `string[]` | `{ 'InsertEnter' }`  | Autocmd events that trigger restore saved IME state      |
| `normalize_on` | `string[]` | `{ 'FocusGained' }`  | Autocmd events that trigger IME normalization            |
| `delay`        | `number`   | `100`                | Delay in ms before normalization check (deferred)        |
| `enable_log`   | `boolean`  | `true`               | Enable logging via `logger.nvim` (no-op if not installed) |

### switch_key

The key combination used to toggle IME. Parsed into Windows virtual key codes
and sent via `keybd_event`. This **must match** the toggle key configured in
your Windows IME settings.

**Supported key names:**

| Key     | VK Code  |
| ------- | -------- |
| `ctrl`  | `0x11`   |
| `shift` | `0x10`   |
| `alt`   | `0x12`   |
| `space` | `0x20`   |
| `win`   | `0x5B`   |

Combine with `+`:

```lua
switch_key = 'ctrl+space'  -- Ctrl+Space (default)
switch_key = 'shift'       -- Shift alone
switch_key = 'ctrl+shift'  -- Ctrl+Shift
```

You can also use raw hex VK codes directly:

```lua
switch_key = '0x11+0x20'   -- Same as ctrl+space
```

### Examples

Use `Shift` as the IME toggle key:

```lua
require('smart-ime').setup({
    switch_key = 'shift',
})
```

Disable logging:

```lua
require('smart-ime').setup({
    enable_log = false,
})
```

Add `CmdlineEnter`/`CmdlineLeave` for command-line mode support:

```lua
require('smart-ime').setup({
    save_on = { 'InsertLeave', 'CmdlineLeave' },
    restore_on = { 'InsertEnter', 'CmdlineEnter' },
})
```

## License

MIT

