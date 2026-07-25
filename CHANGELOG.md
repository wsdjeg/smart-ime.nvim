# Changelog

## [2.0.0](https://github.com/wsdjeg/smart-ime.nvim/compare/v1.0.0...v2.0.0) (2026-07-25)


### ⚠ BREAKING CHANGES

* Removed im-select dependency entirely. IME switching now uses Windows keybd_event API via PowerShell exclusively.

### Features

* add engine option with powershell fallback ([fbae647](https://github.com/wsdjeg/smart-ime.nvim/commit/fbae6477d32607b019d03eb546df89e7566b32b3))
* add setup opts ([5525f8d](https://github.com/wsdjeg/smart-ime.nvim/commit/5525f8d2db81d90ebd79697fcb991f5eebe39c03))


### Bug Fixes

* add delay before IM switch on FocusGained event ([96e960d](https://github.com/wsdjeg/smart-ime.nvim/commit/96e960d9ecac318146796cc6cfa644987c71381f))
* always switch to english on InsertLeave even when detection fails ([a3a4fbd](https://github.com/wsdjeg/smart-ime.nvim/commit/a3a4fbdac9149a4a04c9dbe6168392593c273b12))
* expand ~ in imselect path and guard against empty IM state ([c7b3f7c](https://github.com/wsdjeg/smart-ime.nvim/commit/c7b3f7c96fc3eb7599856d3841eec53758664585))
* switch to english after saving IM state on InsertLeave ([5d4c309](https://github.com/wsdjeg/smart-ime.nvim/commit/5d4c309269f58ccc1c7322550c3a9edee727fd48))
* use :wait() instead of callback for InsertLeave IM switch ([00f1fd5](https://github.com/wsdjeg/smart-ime.nvim/commit/00f1fd5c722f615ccad8fd9f7c7bc850c3fe2d22))
* use keybd_event API instead of SendKeys for PowerShell IME fallback ([78e7eac](https://github.com/wsdjeg/smart-ime.nvim/commit/78e7eac98d9d250802c295099e9941832b02bb20))
* **windows:** use file redirect for query and add PowerShell fallback ([3e83750](https://github.com/wsdjeg/smart-ime.nvim/commit/3e8375007dc04f5cf89ba56db7fe4ac4e5906ed3))


### Code Refactoring

* remove imselect support, use PowerShell only ([f27a64c](https://github.com/wsdjeg/smart-ime.nvim/commit/f27a64c74fac52df1d7718d9b13a295c5be00912))
* remove powershell command logging ([326c621](https://github.com/wsdjeg/smart-ime.nvim/commit/326c6212363670fb2fe7743388f4183f18227854))


### Documentation

* align README structure with picker.nvim style ([97675c5](https://github.com/wsdjeg/smart-ime.nvim/commit/97675c5b0f151ebb429f3e9a74e40041f20e0bc4))
* fix license from MIT to GPL-3.0 ([74dbc16](https://github.com/wsdjeg/smart-ime.nvim/commit/74dbc166d43052af615ab6c453a0cf76e818264c))
* rewrite README for PowerShell-only approach ([d1f09b4](https://github.com/wsdjeg/smart-ime.nvim/commit/d1f09b46b63d82795441971a49ef6083fa9c66c0))


### Tests

* add IME switching behavior tests ([46d4510](https://github.com/wsdjeg/smart-ime.nvim/commit/46d4510caa7eab46b3613f67abc6c0e4efb6809f))

## 1.0.0 (2025-12-17)


### Features

* init version ([911e914](https://github.com/wsdjeg/smart-ime.nvim/commit/911e914b4169b2417c775bcbeac5be809386338c))
