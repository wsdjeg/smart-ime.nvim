# smart-ime.nvim

Smart per-buffer IME switching for Neovim (Windows).

[![Run Tests](https://github.com/wsdjeg/smart-ime.nvim/actions/workflows/test.yml/badge.svg)](https://github.com/wsdjeg/smart-ime.nvim/actions/workflows/test.yml)
[![GitHub License](https://img.shields.io/github/license/wsdjeg/smart-ime.nvim)](LICENSE)
[![GitHub Issues or Pull Requests](https://img.shields.io/github/issues/wsdjeg/smart-ime.nvim)](https://github.com/wsdjeg/smart-ime.nvim/issues)
[![GitHub commit activity](https://img.shields.io/github/commit-activity/m/wsdjeg/smart-ime.nvim)](https://github.com/wsdjeg/smart-ime.nvim/commits/master/)
[![GitHub Release](https://img.shields.io/github/v/release/wsdjeg/smart-ime.nvim)](https://github.com/wsdjeg/smart-ime.nvim/releases)
[![luarocks](https://img.shields.io/luarocks/v/wsdjeg/smart-ime.nvim)](https://luarocks.org/modules/wsdjeg/smart-ime.nvim)

## Features

- **Per-buffer IME state**  
  Remembers input method state separately for each buffer.

- **Automatic IME switching**

  - Switches to English when leaving Insert mode
  - Restores previous IME when re-entering Insert mode

- **Focus-aware normalization**  
  Ensures IME state is consistent when Neovim regains focus.

- **Zero external dependencies**  
  Uses Windows `keybd_event` API via PowerShell — no `im-select` binary needed.

- **Async & non-blocking**  
  Uses `vim.system()` for asynchronous IME switching.

- **Optional logging**  
  Integrates with `logger.nvim` when available.

- **Minimal & predictable behavior**  
  Reacts only to editor events, no background polling.

## How it works

1. On `InsertLeave`, IME is switched to English to ensure normal-mode safety.
2. The buffer's IME state is tracked (defaults to Chinese).
3. On `InsertEnter`, the previously saved IME state is restored.
4. On focus gain (`FocusGained`), IME state is normalized based on current mode.

All switching is done by sending the configured toggle key (e.g. `Ctrl+Space`)
via the Windows `keybd_event` API through PowerShell.

## Installation

Using [nvim-plug](https://github.com/wsdjeg/nvim-plug):

```lua
return {
    'wsdjeg/smart-ime.nvim',
    opts = {},
}
```

Using [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
    'wsdjeg/smart-ime.nvim',
    opts = {},
}
```

## Configuration

| Option         | Type       | Default            | Description                                            |
| -------------- | ---------- | ------------------ | ------------------------------------------------------ |
| `switch_key`   | `string`   | `'ctrl+space'`     | IME toggle key (e.g. `'ctrl+space'`, `'shift'`)        |
| `save_on`      | `string[]` | `{ 'InsertLeave' }`| Events to save IME state                               |
| `restore_on`   | `string[]` | `{ 'InsertEnter' }`| Events to restore IME state                            |
| `normalize_on` | `string[]` | `{ 'FocusGained' }`| Events to normalize IME state                          |
| `delay`        | `number`   | `100`              | Delay (ms) for deferred normalization                  |
| `enable_log`   | `boolean`  | `true`             | Enable logging via `logger.nvim`                       |

### switch_key

The key combination used to toggle IME. Parsed into virtual key codes and
sent via `keybd_event`. Supported keys:

| Key     | VK Code |
| ------- | ------- |
| `ctrl`  | `0x11`  |
| `shift` | `0x10`  |
| `alt`   | `0x12`  |
| `space` | `0x20`  |
| `win`   | `0x5B`  |

Combine with `+`, e.g. `'ctrl+space'`, `'shift'`, `'ctrl+shift'`.

You can also use raw hex codes: `'0x11+0x20'`.

### Example

```lua
require('smart-ime').setup({
    switch_key = 'ctrl+space',
    save_on = { 'InsertLeave' },
    restore_on = { 'InsertEnter' },
    normalize_on = { 'FocusGained' },
    delay = 100,
    enable_log = true,
})
```

## License

MIT

