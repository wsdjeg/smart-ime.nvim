# smart-ime.nvim

Smart per-buffer IME switching for Neovim.

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

- **Async & non-blocking**  
  Uses `vim.system()` for asynchronous IME switching.

- **Multiple engines**

  - `imselect`: uses [im-select-mspy](https://github.com/daiyanya/im-select-mspy) for querying and switching (Windows)
  - `powershell`: uses PowerShell `keybd_event` API for switching (Windows, no external tool needed)
  - `auto` (default): tries `imselect` first, falls back to `powershell` if it fails

- **Optional logging**  
  Integrates with `logger.nvim` when available.

- **Minimal & predictable behavior**  
  Reacts only to editor events, no background polling.

## How it works

1. On `InsertLeave`, the current IME state is saved per buffer.
2. IME is switched to English to ensure normal-mode safety.
3. On `InsertEnter`, the previously saved IME state is restored.
4. On focus gain (`FocusGained`), IME state is normalized based on current mode.

## Installation

Using [nvim-plug](https://github.com/wsdjeg/nvim-plug):

```lua
return {
    'wsdjeg/smart-ime.nvim',
    opts = {
        imselect = '~/bin/im-select-mspy.exe',
    },
}
```

### Windows (PowerShell engine, no external tool needed)

If `im-select-mspy.exe` doesn't work on your system, you can use the
PowerShell engine instead. This uses the Windows `keybd_event` API to
send the IME toggle key directly — no external binary required:

```lua
return {
    'wsdjeg/smart-ime.nvim',
    opts = {
        engine = 'powershell',
        switch_key = 'ctrl+space',
    },
}
```

## Configuration

| Option         | Type       | Default            | Description                                                    |
| -------------- | ---------- | ------------------ | -------------------------------------------------------------- |
| `engine`       | `string`   | `'auto'`           | Switching engine: `'auto'`, `'powershell'`, or `'imselect'`   |
| `switch_key`   | `string`   | `'ctrl+space'`     | IME toggle key for PowerShell engine (e.g. `'shift'`)          |
| `imselect`     | `string?`  | `nil`              | Path to `im-select` tool (required for `'auto'`/`'imselect'`)  |
| `save_on`      | `string[]` | `{ 'InsertLeave' }`| Events to save IME state                                       |
| `restore_on`   | `string[]` | `{ 'InsertEnter' }`| Events to restore IME state                                    |
| `normalize_on` | `string[]` | `{ 'FocusGained' }`| Events to normalize IME state                                  |
| `delay`        | `number`   | `100`              | Delay (ms) for deferred normalization                          |
| `enable_log`   | `boolean`  | `true`             | Enable logging via `logger.nvim`                               |

### Engines

#### `auto` (default)

Tries `imselect` for querying and switching. If the query returns empty
or fails, automatically falls back to `powershell` for the rest of the
session.

```lua
require('smart-ime').setup({
    engine = 'auto',
    imselect = '~/bin/im-select-mspy.exe',
    switch_key = 'ctrl+space',
})
```

#### `powershell`

Skips `imselect` entirely. Uses PowerShell `keybd_event` API to send the
IME toggle key. No external tool needed. Best for Windows systems where
`im-select-mspy.exe` doesn't work.

```lua
require('smart-ime').setup({
    engine = 'powershell',
    switch_key = 'ctrl+space',
})
```

#### `imselect`

Only uses `imselect` for querying and switching. No fallback to
PowerShell.

```lua
require('smart-ime').setup({
    engine = 'imselect',
    imselect = '~/bin/im-select-mspy.exe',
})
```

## License

MIT

