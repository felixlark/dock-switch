# dock-switch
Quickly switch among applications in the macOS Dock with one global hotkey.

## Documentation
- Sphinx docs live in `docs/` (start at `docs/index.rst`).
- `README.md` stays as the quick-start / behavior overview.

<a id="release-record-gokit5-serial-button-control"></a>

## 发版更新：GoKit5 串口按键控制
dock-switch 现在可以通过串口监听连接的 GoKit5 / 机智云控制器，把硬件按键信息转换成鼠标屏幕切换动作。刷入匹配固件后，控制器可以向 dock-switch 发送主机按键消息，把鼠标移动到指定屏幕中心、点击激活该点窗口，并显示水波纹反馈。

- dock-switch 启动后会自动开始串口监听。
- GoKit5 USB 串口会自动识别，也可以用 `GOKIT5_SERIAL_PORT=/dev/cu.usbmodem...` 固定端口。
- 物理按键移动鼠标并点击激活目标点窗口：minus = 左侧边屏，plus = 内置屏，voice = 外接屏，green/switch = 右侧边屏；目标外屏未连接时退回内置主屏。
- `dock-switch-cli gokit5-status` 可以查看监听是否启用、是否运行，以及当前使用的串口。
- 设置 `DOCK_SWITCH_GOKIT5=0` 可以关闭串口监听。

## Screenshots
This repository intentionally does not commit desktop screenshots. Local screenshots
often expose menu bar state, Dock contents, account badges, and workspace details.

## How It Works
- Press `F20` to open the floating launcher UI.
- Press the shown key for an app to focus it.
- Karabiner should open SmartShadow and ChatGPT directly for the local `F3` and `F6` shortcuts. Left and right `Shift` should keep the default system behavior, with any legacy Shift launcher mappings removed.
- Press an arrow key to fill the frontmost window on a physical display:
  - `←` left side display
  - `→` right side display
  - `↑` external display
  - `↓` internal display
- Press `【` to tile the frontmost window to the left half of its current display.
- Press `】` to tile the frontmost window to the right half of its current display.
- Press `F6` to open `ChatGPT` directly on the right side display, maximized to the display work area.
- Press `F20` then left `Shift` to focus or open `Codex` on the external display, maximized to the display work area.
- Press `F20` then right `Shift` to focus or open `Claude` on the right side display, maximized to the display work area.
- Press `F3` to open `SmartShadow` directly on the left side display, maximized to the display work area.
- Press left `Command` to focus or open `System Settings` on the internal display, maximized to the display work area.
- Press right `Command` for a reserved no-op.
- Press `\` to focus or open `Terminal` on the right side display, maximized to the display work area.
- App activation moves the pointer to the center of the activated or placed window; arrow display moves keep moving the pointer to the center of the target display.
- A connected GoKit5 controller flashed with [open-embodied](https://github.com/felixlark/open-embodied) moves the pointer across displays and clicks the target point to activate the window there, without launching, creating, or moving app windows: minus = left side, plus = internal, voice = external, green/switch = right side. Missing external targets fall back to the internal main display.
- The UI closes automatically after a selection.

## Browser Fixed Placement
This project supports per-app window placement through `src/config.json`.

Example:

```json
{
  "name": "Safari",
  "key": "S",
  "screen": "1",
  "placement": "internal_fill"
}
```

```json
{
  "name": "Google Chrome",
  "key": "G",
  "screen": "1",
  "placement": "internal_fill"
}
```

```json
{
  "name": "GitHub",
  "key": "H",
  "screen": "1",
  "kind": "web_app",
  "placement": "internal_fill",
  "open_path": "~/Applications/Chromium Apps.localized/GitHub.app",
  "app_url": "https://github.com/repos?q=owner%3A%40me+sort%3Aupdated"
}
```

When triggered from dock-switch, Safari and Google Chrome are maximized on the internal display work area.
Web apps with `kind: "web_app"` use `internal_fill` by default.
The `X` web app is maximized on the internal display work area.
The `小红书` web app is maximized on the internal display work area.
The `GitHub` web app is maximized on the internal display work area.
The `X`, `小红书`, and `GitHub` web app bundles can target the signed-in Chrome-family profile used by their app shims.
Xiaohongshu Web App is available on `R` in the current default config.
Google Chrome is available on `G` in the current default config.
GitHub Web App is available on `H` in the current default config.
ChatGPT, Codex, SmartShadow, Claude, and Command shortcuts render in the HUD with default Dock labels: `F6` for ChatGPT, `L⇧` for left Shift / Codex, `F3` for SmartShadow, `R⇧` for right Shift / Claude, and `⌘` for left/right `Command`. The app shortcuts are configurable in Dock Switch Settings while remaining excluded from ordinary fallback numbering.
Left `Command` opens System Settings on the internal display with `internal_fill`. Inside dock-switch's launcher, left `Shift` opens Codex on the external display with `external_fill`, right `Shift` opens Claude on the right side display with `side_right_fill`, and `F6` opens ChatGPT on the right side display with `side_right_fill`. Direct launcher shortcuts read the saved app placement even when the launcher overlay is closed. Karabiner single-key shortcuts are limited to the direct `F3` and `F6` exceptions: they open SmartShadow and ChatGPT, then use dock-switch placement for `side_left_fill` and `side_right_fill`. Legacy Karabiner left/right `Shift` launcher mappings should be removed so Shift returns to the default system behavior. `\` opens Terminal on the right side display with `side_right_fill`. Right `Command` is intentionally reserved as a no-op. External targets that are offline fall back to the internal main display.
If no external display is available, `external_right_half` falls back to the right half of the internal display work area.
If no external display is available, `external_left_half` falls back to the left half of the internal display work area.

## Remember Last Window Size/Position
By default, dock-switch remembers the last known window bounds (x/y/width/height) for each app and restores them when that app is reopened from dock-switch.

- Window state is kept in memory for the current app session (no disk persistence).
- This includes maximized-like window sizes because the actual bounds are restored.
- Apps with explicit `placement` (for example `external_fill`, `side_right_fill`, or `internal_fill`) keep that placement behavior.
- Apps with `kind: "web_app"` default to `internal_fill` unless `placement` overrides it.
- `open_path` can pin a launcher item to an exact app bundle, which is useful for Chrome web app shims stored under `~/Applications/Chrome Apps.localized`.
- `app_url` lets dock-switch identify a Chrome `--app=...` window by pid when Accessibility sees only `Google Chrome`.

To disable restore for a specific app, add:

```json
{
  "name": "Terminal",
  "key": "\\",
  "screen": "side_right",
  "placement": "side_right_fill",
  "remember_window_state": false
}
```

## Installation
- Download a release from [GitHub Releases](https://github.com/felixlark/dock-switch/releases).

## Build From Source
1. Clone this repository.
2. Install dependencies:
   - `yarn install`
3. Run locally:
   - `yarn go`
4. Run tests:
   - `node --test test/*.test.js`
5. Build unsigned app bundle:
   - `yarn dist`
6. Build signed app bundle (requires signing identity):
   - `yarn dist:signed`

## CLI
`dock-switch-cli` is the canonical command-line entrypoint for window placement, display inspection, and pid/profile-bound Chrome targeting.

Examples:

```bash
dock-switch-cli displays
dock-switch-cli gokit5-status
dock-switch-cli codex-display --target external
dock-switch-cli place --app "Terminal" --placement side_right_fill
dock-switch-cli place --pid 12345 --placement external_right_half
dock-switch-cli move --app "Terminal" --x 0 --y 25 --w 1512 --h 875
dock-switch-cli move --pid 12345 --x 0 --y 25 --w 1512 --h 875
dock-switch-cli get-chrome-window --profile-dir /tmp/chrome_profile-XXXXXX
dock-switch-cli move-chrome-window --profile-dir /tmp/chrome_profile-XXXXXX --x 713 --y -1410 --w 1280 --h 1410
```

Notes:

- If `dock-switch-cli` is not on your PATH, run it as `node bin/dock-switch-cli.js ...` from this repo.
- `--pid` is useful when you need to target one managed window from a multi-window app such as Google Chrome.
- `get-chrome-window` and `move-chrome-window` target the exact Chrome window for a specific `--user-data-dir` profile through Chrome DevTools when a profile-bound helper still needs window placement.
- If the dock-switch control socket is not running, the CLI launches `/Applications/dock-switch.app` and retries automatically.
- `displays` prints JSON with Electron display bounds and work areas.
- `gokit5-status` prints the runtime serial listener state and selected port.
- `codex-display` focuses an existing Codex window on the target display when available. If no Codex window exists on that display, it creates one there without moving windows from other displays. It always centers the pointer on the target display work area so repeated physical key presses do not drift with window bounds.
- The GoKit5 serial listener auto-detects the Espressif USB JTAG/serial device and can be pinned with `GOKIT5_SERIAL_PORT=/dev/cu.usbmodem...`; set `DOCK_SWITCH_GOKIT5=0` to disable it. The matching firmware lives at [felixlark/open-embodied](https://github.com/felixlark/open-embodied).

## Managed Chrome Windows
Codex browser work should use the official Chrome plugin for signed-in Google Chrome state and the in-app browser for unauthenticated local or public pages. The profile-bound Chrome CLI helpers are retained only for lower-level window placement.

Typical flow:

```bash
dock-switch-cli displays
dock-switch-cli get-chrome-window --profile-dir /tmp/chrome_profile-XXXXXX
dock-switch-cli move-chrome-window --profile-dir /tmp/chrome_profile-XXXXXX --x 713 --y -1410 --w 1280 --h 1410
```

## Configuration
App key/display mapping is stored in `src/config.json` under `dock_items`.

## Permissions and First Run
- Map a key to `F20` (for example with [Karabiner-Elements](https://github.com/pqrs-org/Karabiner-Elements)).
- To install the local single-key launcher mappings for `F3` and `F6`, run `yarn karabiner:f20`. The generated Karabiner rule opens SmartShadow directly on `F3` and ChatGPT directly on `F6`; it also removes legacy left/right `Shift` launcher mappings so Shift returns to the default system behavior.
- SmartShadow's direct `F3` path opens `/Applications/SmartShadow.app` and uses dock-switch placement with `side_left_fill`.
- Keep the installed app in macOS `Open at Login` so the global shortcut and control socket are available after login.
- On first use, dock-switch prompts for required macOS permissions:
  - Accessibility (control UI elements / Dock metadata)
- If previously denied, re-enable in Privacy & Security:
  - Accessibility: `Privacy & Security > Accessibility`
- macOS may warn about an unidentified developer depending on how the app is built/signed.

## Project Notes
- Electron entry point: `src/main.js`
- Renderer/UI logic: `src/index.js`
- Dock metadata provider: native Node addon (`native/dock-query`)
- Canonical automation entrypoint: `bin/dock-switch-cli.js`
