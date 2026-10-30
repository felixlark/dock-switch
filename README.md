# dock-switch

`dock-switch` is a macOS utility for launching and arranging application windows across displays. It provides a floating launcher, keyboard shortcuts, a command-line interface, configurable app/display mappings, and optional GoKit5 serial-button integration.

## Features

- Open or focus configured applications from a floating launcher.
- Move or tile windows on the internal, external, left-side, or right-side display; symbolic display targets adapt to the connected display layout.
- Inspect displays and control placement by application name or process ID with `dock-switch-cli`.
- Target a Chrome window by its profile when profile-specific placement is needed.
- Optionally listen to a compatible GoKit5 controller over USB serial. The listener can auto-detect its port or use `GOKIT5_SERIAL_PORT`; disable it with `DOCK_SWITCH_GOKIT5=0`.

See the [Sphinx documentation](docs/index.rst) and the [shortcut verification guide](docs/shortcut-verification.rst) for additional detail.

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
