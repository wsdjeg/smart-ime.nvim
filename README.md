# smart-ime.nvim

Smart per-buffer IME switching for Neovim.

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
  Uses `vim.system()` for asynchronous IME querying and switching.

- **Optional logging**  
  Integrates with `logger.nvim` when available.

- **Minimal & predictable behavior**  
  Reacts only to editor events, no background polling.

## How it works

1. On `InsertLeave`, the current IME state is queried and saved per buffer.
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
