# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.1] - 2026-10-09

### Fixed

- Resolve and activate Feishu by its canonical application identity (`com.electron.lark`), unify Feishu/Lark/飞书 names, exclude similarly named helpers, and preserve the F shortcut and configured window placement. Add Node and Swift regression coverage.

### Security

- Update dependencies in the lockfile: brace-expansion to 2.1.7, undici to 6.28.1, xmldom to 0.8.15 and 0.9.12, fast-uri to 3.1.8, and js-yaml to 4.3.2.

## [1.0.2] - 2026-10-23

### Added

- Add GoKit5 serial-button integration for display targeting, pointer activation, and command-modified phrase input, with automatic port detection and status reporting.
- Add display inspection and Codex/browser placement commands to `dock-switch-cli`, including PID and profile-bound Chrome window targeting.

### Changed

- Improve application reopening and activation so launcher selections behave like normal Dock clicks, including Feishu/Lark identity resolution and configured placement restoration.
- Defer placement until an application has finished opening, and fall back to the internal display when an external target is unavailable.
- Restore Caps Lock input-source switching and configure the right-Command F20 HUD mapping while preserving ordinary Command chords and Shift behavior.
- Update public documentation, build output defaults, and native bundle metadata for the 1.0.2 release.

### Fixed

- Preserve compact Device Hub window sizes while centering them on the selected display or half.
- Add bounded shortcut-state recording and physical-key acceptance guidance.

## [1.0.0]

- Initial tagged release.

[1.0.1]: https://github.com/felixlark/dock-switch/compare/1.0.0...1.0.1
[1.0.2]: https://github.com/felixlark/dock-switch/compare/1.0.1...1.0.2
[1.0.0]: https://github.com/felixlark/dock-switch/releases/tag/1.0.0
