# dock-switch

`dock-switch` is a macOS utility for launching and arranging application windows across displays. It provides a floating launcher, keyboard shortcuts, a command-line interface, configurable app/display mappings, and optional GoKit5 serial-button integration.

## Features

- Open or focus configured applications from a floating launcher.
- Move or tile windows on the internal, external, left-side, or right-side display; symbolic display targets adapt to the connected display layout.
- Inspect displays and control placement by application name or process ID with `dock-switch-cli`.
- Target a Chrome window by its profile when profile-specific placement is needed.
- Optionally listen to a compatible GoKit5 controller over USB serial. The listener can auto-detect its port or use `GOKIT5_SERIAL_PORT`; disable it with `DOCK_SWITCH_GOKIT5=0`.

See the [Sphinx documentation](docs/index.rst) and the [shortcut verification guide](docs/shortcut-verification.rst) for additional detail.

## Codex workspace on chat switch

The native app observes public macOS Accessibility notifications for `com.openai.codex`.
On a changed chat view or focused Codex window, it presses the header's **New tab**
button only when **Chat tabs** is absent. An already visible workspace is left alone;
Cmd+T remains Codex's **New tab** command. Reopening a hidden workspace uses Codex's
New tab action and can add one blank tab; it does not add tabs on subsequent switches
while that workspace is visible.

Turn this off in **Settings → Codex 切换聊天时展开已关闭的工作区**. The switch takes effect
immediately (observer subscriptions refresh within two seconds), independently of the
launcher table's Save button. The preference lives in the app's macOS preferences,
outside its signed bundle, and survives reinstalling the app.

The observer shares the existing app lifecycle and Accessibility authorization, detaches
on quit/disable/permission loss/Codex exit, and reattaches on Codex launch. Starting or
reenabling seeds the current view without reopening a manually closed workspace.
Only public window/header metadata and opaque AX object identities are used; conversation
and composer subtrees are excluded. No keyboard hook, private database, Codex bundle
change, or additional daemon is involved.

Compatibility: targets the observed Codex 26.1023.51421 English AX labels.
A standard chat header with `Chat toolbar` and either `Chat tabs` or a `New tab` button
is required. Settings, archived-chat pages, full-view layouts without that header, and
unknown/localized layouts are skipped. Toolbar identities distinguish equal titles.
Public shell/dialog notifications invalidate the baseline through Rename; the first
recognized post-dialog view only seeds it, even if Rename remounts the toolbar.
AX is not a documented task identity API. A future view remount or missing/late
notification can require revalidation.
Disable/remove this adapter when Codex provides a supported always-open workspace option.
See [integration and acceptance notes](docs/codex-workspace.md).
Run `node scripts/codex-workspace-status.js` for read-only subscription, trust, event and
action counters (no chat titles or contents).

## Custom phrases (local Wubi component)

Open **Settings → 自定义短语** to enable, record and apply the global
selected-text shortcut (default **Command+Shift+grave**, the key left of `1`).
Dock-switch registers the physical key code with macOS, independently of the
current input source. Changes take effect without restarting the target app.
Recording temporarily releases the active combination; Escape, leaving the
settings window or quitting Settings restores it. Failed registration keeps
the previous working combination. The preference survives app reinstallations.

This optional integration requires the already provisioned local component at
`~/Library/Application Support/wubi-phrase/`: `encode.py`, `wubi86.dict.yaml`,
`known-phrases.json`, `db-candidate/append_phrase.py`, and
`db-candidate/schema.json`. These user-specific files are not bundled or uploaded.
Without the component the shortcut is not registered. The component is responsible
for schema checks, consistent backups and append-only writes to the user's macOS
text replacements; this is an unsupported local storage adapter, not an Apple API.
Existing phrases remain intact; code collisions require confirmation.

The native app reads only the selected text of the focused Accessibility element,
rejects secure text fields, and displays a nonactivating tooltip. It does not use
the clipboard or AppleScript. A recognized legacy **选词加入五笔短语** service
shortcut is retired after successful native registration; its original value is
backed up in the app's preferences, preserving other global shortcuts.
After a new phrase is stored, the app uses public Text Input Source Services to
switch once between enabled Apple Wubi and English sources and restore the original
source. It skips the refresh if the foreground app or input source has changed;
existing phrases, failures and previews never switch input sources. If switching
is unavailable or fails, the tooltip gives a manual recovery hint. Input-client
caching can still vary; reopen that client if the new phrase remains absent.
The nonactivating tooltip is centered above the bottom of the active window's
display, inside its usable area, independent of the mouse position. No input
service is restarted and no app is activated by the refresh.

## Install

Download the latest macOS app from [GitHub Releases](https://github.com/felixlark/dock-switch/releases) and move `dock-switch.app` into `/Applications`. On first use, grant Accessibility access when prompted (System Settings → Privacy & Security → Accessibility); it is used to inspect Dock items and control window placement. macOS may also request Automation access to control the Dock. Only enable optional input/automation permissions when using the corresponding feature.

The app is not required to launch at login, but adding it to Login Items keeps its global launcher and control socket available after sign-in. Unsigned or locally built apps may trigger the standard macOS unidentified-developer warning.

## Build from source

Requirements: macOS, Xcode Command Line Tools (Swift), Node.js, Yarn, and (for shortcut configuration) [Karabiner-Elements](https://karabiner-elements.pqrs.org/).

```bash
git clone https://github.com/felixlark/dock-switch.git
cd dock-switch
yarn install
yarn test
yarn dist
```

`yarn dist` builds and installs the native app at `/Applications/dock-switch.app`; installation requires a usable code-signing identity. To choose a local build output directory, set `DOCK_SWITCH_BUILD_ROOT`. The default is `~/Library/Caches/dock-switch/build`. SwiftPM scratch/build caches are stored under `~/Library/Caches/dock-switch/` and can be overridden with `DOCK_SWITCH_SWIFT_SCRATCH` and `DOCK_SWITCH_SWIFT_CACHE`. To package a local launcher configuration, set `DOCK_SWITCH_CONFIG_SOURCE` to its JSON file before building.

`yarn go` starts the development Electron app. `yarn karabiner:f20` configures the optional right-Command-to-F20 launcher mapping; review the generated Karabiner rule before enabling it. The launcher can also be opened directly with F20.

## CLI

Use the installed `dock-switch-cli` command, or run `node bin/dock-switch-cli.js` from the repository:

```bash
dock-switch-cli displays
dock-switch-cli place --app "Terminal" --placement external_right_half
dock-switch-cli place --pid 12345 --placement side_right_fill
dock-switch-cli move --app "Terminal" --x 0 --y 25 --w 1200 --h 800
dock-switch-cli codex-display --target external
dock-switch-cli gokit5-status
```

`displays` reports current display bounds and work areas as JSON. `place` accepts an application name or PID and a supported placement; `move` accepts an application name or PID and explicit bounds. `codex-display` targets a symbolic display (`side_left`, `external`, `side_right`, or `internal`). `get-chrome-window` and `move-chrome-window` require `--profile-dir` and operate on that Chrome profile. Run `dock-switch-cli` without arguments for the complete command syntax. When the control socket is not running, the CLI attempts to launch `/Applications/dock-switch.app`.

## Configuration

App shortcuts and display placement are configured in `src/config.json` under `dock_items`. Prefer symbolic display names and placement values rather than numeric display indexes, which vary by machine. For example:

```json
{
  "name": "Terminal",
  "key": "T",
  "screen": "side_right",
  "placement": "side_right_fill"
}
```

Use `open_path` to specify an app bundle path when the application name is ambiguous. `app_url` can identify a Chrome app window. The settings app can edit local key and placement mappings; set `DOCK_SWITCH_CONFIG_SOURCE` when a non-default configuration should be included in a build.

## Permissions and privacy

- **Accessibility:** required for Dock metadata and window inspection/placement. Grant access to dock-switch in System Settings → Privacy & Security → Accessibility.
- **Automation:** macOS may request permission when dock-switch controls or restores the Dock.
- **Input Monitoring:** used only for global keyboard shortcut handling where macOS requests it.
- **GoKit5 serial:** optional; serial access is used only when the listener is enabled. `GOKIT5_SERIAL_PORT` selects a port, and `DOCK_SWITCH_GOKIT5=0` disables the listener.

The repository intentionally excludes desktop screenshots because they can expose local accounts and workspace details. Do not include local screenshots or machine-specific configuration in public issues or releases.

## Development references

- Electron entry point: `src/main.js`
- Renderer/UI: `src/index.js`
- Native Dock metadata provider: `native/dock-query`
- CLI entry point: `bin/dock-switch-cli.js`
- GoKit5 firmware project: [felixlark/open-embodied](https://github.com/felixlark/open-embodied)
