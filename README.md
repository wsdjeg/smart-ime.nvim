# smart-ime.nvim

`smart-ime.nvim` is a lightweight per-buffer IME switching plugin for Neovim on Windows.
It automatically switches your input method to English when leaving Insert mode,
and restores the previous state when re-entering — all without any external binaries.

[![Run Tests](https://github.com/wsdjeg/smart-ime.nvim/actions/workflows/test.yml/badge.svg)](https://github.com/wsdjeg/smart-ime.nvim/actions/workflows/test.yml)
[![GitHub License](https://img.shields.io/github/license/wsdjeg/smart-ime.nvim)](LICENSE)
[![GitHub Issues or Pull Requests](https://img.shields.io/github/issues/wsdjeg/smart-ime.nvim)](https://github.com/wsdjeg/smart-ime.nvim/issues)
[![GitHub commit activity](https://img.shields.io/github/commit-activity/m/wsdjeg/smart-ime.nvim)](https://github.com/wsdjeg/smart-ime.nvim/commits/master/)
[![GitHub Release](https://img.shields.io/github/v/release/wsdjeg/smart-ime.nvim)](https://github.com/wsdjeg/smart-ime.nvim/releases)
[![luarocks](https://img.shields.io/luarocks/v/wsdjeg/smart-ime.nvim)](https://luarocks.org/modules/wsdjeg/smart-ime.nvim)

<!-- vim-markdown-toc GFM -->

- [✨ Features](#-features)
- [📦 Installation](#-installation)
- [🔧 Configuration](#-configuration)
- [🔑 switch_key](#-switch_key)
- [💡 Examples](#-examples)
- [❓ FAQ](#-faq)
- [📣 Self-Promotion](#-self-promotion)
- [💬 Feedback](#-feedback)
- [🙏 Credits](#-credits)
- [📄 License](#-license)

<!-- vim-markdown-toc -->

## ✨ Features

- **Per-buffer IME state** - Each buffer remembers its own input method state
- **Automatic switching** - English on `InsertLeave`, restore on `InsertEnter`
- **Focus normalization** - Ensures consistent IME state when Neovim regains focus
- **Zero dependencies** - No `im-select` or other external binaries needed
- **Async & non-blocking** - Uses `vim.system()` for all PowerShell calls
- **Optional logging** - Integrates with [logger.nvim](https://github.com/wsdjeg/logger.nvim) when available
- **No background polling** - Reacts only to editor events

## 📦 Installation

smart-ime.nvim works with all major Neovim plugin managers.
Neovim 0.10+ and Windows with PowerShell are required.

- **Using [nvim-plug](https://github.com/wsdjeg/nvim-plug)**

  ```lua
  require('plug').add({
    {
      'wsdjeg/smart-ime.nvim',
    },
  })
  ```

- **Using [lazy.nvim](https://github.com/folke/lazy.nvim)**

  ```lua
  {
    'wsdjeg/smart-ime.nvim',
    event = 'InsertEnter',
    opts = {},
  }
  ```

- **Using [packer.nvim](https://github.com/wbthomason/packer.nvim)**

  ```lua
  use({
    'wsdjeg/smart-ime.nvim',
    config = function()
      require('smart-ime').setup({})
    end,
  })
  ```

- **Using [luarocks](https://luarocks.org/)**

  ```
  luarocks install smart-ime.nvim
  ```

## 🔧 Configuration

This example shows a basic setup for smart-ime.nvim.
The `switch_key` option must match the toggle key configured in your Windows IME settings.

```lua
require('smart-ime').setup({
  switch_key = 'ctrl+space',        -- IME toggle key (must match Windows IME setting)
  save_on = { 'InsertLeave' },      -- Events to save IME state and switch to English
  restore_on = { 'InsertEnter' },   -- Events to restore saved IME state
  normalize_on = { 'FocusGained' }, -- Events to normalize IME state
  delay = 100,                      -- Delay (ms) for deferred normalization
  enable_log = true,                -- Enable logging via logger.nvim (no-op if not installed)
})
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

## 🔑 switch_key

The key combination used to toggle IME. Parsed into Windows virtual key codes
and sent via `keybd_event`. This **must match** the toggle key configured in
your Windows IME settings.

**Supported key names:**

| Key     | VK Code |
| ------- | ------- |
| `ctrl`  | `0x11`  |
| `shift` | `0x10`  |
| `alt`   | `0x12`  |
| `space` | `0x20`  |
| `win`   | `0x5B`  |

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

## 💡 Examples

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

## ❓ FAQ

1. How does the plugin switch IME?

   The plugin **simulates your IME toggle key** (e.g. `Ctrl+Space`) via the
   Windows `keybd_event` API through PowerShell. It does not query the current
   IME state — instead, it tracks state per buffer manually (defaulting to
   Chinese on first `InsertLeave`).

2. Why does `switch_key` need to match my Windows setting?

   Since switching is done by simulating a keystroke, the plugin sends whatever
   key you configured. If this doesn't match your actual Windows IME toggle key,
   the keystroke will have no effect on the IME.

3. What if I manually change IME outside Neovim?

   The tracked state may become out of sync. The `FocusGained` normalization
   event helps correct this — when Neovim regains focus, IME is normalized
   based on the current mode.

4. Does this work on macOS or Linux?

   No. The plugin relies on PowerShell and the Windows `keybd_event` API.

## 📣 Self-Promotion

Like this plugin? Star the repository on
GitHub.

Love this plugin? Follow [me](https://wsdjeg.net/) on
[GitHub](https://github.com/wsdjeg) or [Twitter](https://x.com/EricWongDEV).

## 💬 Feedback

If you encounter any bugs or have suggestions, please file an issue in the [issue tracker](https://github.com/wsdjeg/smart-ime.nvim/issues)

## 🙏 Credits

- [im-select.nvim](https://github.com/keaising/im-select.nvim)
- [smartim.nvim](https://github.com/kkharji/smartim.nvim)

## 📄 License

Licensed under GPL-3.0.

