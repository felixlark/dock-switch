# Dock-Switch Runbook

## Repo Scope

- Owner/escalation: repository maintainer for local display/window launcher behavior.
- This repo owns the installed `/Applications/dock-switch.app`, `dock-switch-cli`, Codex display placement helpers, and GoKit5 serial integration.
- It is a maintained macOS utility, not the default browser or Codex automation path.

## Canonical Commands

- Show live displays: `node bin/dock-switch-cli.js displays`
- Place by app: `node bin/dock-switch-cli.js place --app <AppName> --placement external_right_half`
- Place by pid: `node bin/dock-switch-cli.js place --pid <Pid> --placement external_right_half`
- Move by bounds: `node bin/dock-switch-cli.js move --app <AppName> --x <X> --y <Y> --w <W> --h <H>`
- Build/package/install: `yarn dist`
- Tests: `yarn test` or targeted `node --test test/<name>.test.js`

## Routine Operations

| Trigger | Command | Expected Result | Failure Recovery |
| --- | --- | --- | --- |
| Verify display labels before placement work | `node bin/dock-switch-cli.js displays` | Display labels and bounds are current | Re-map display-target logic from live labels before editing config |
| Change launcher/window behavior | `node --test test/<name>.test.js` then `yarn dist` | Tests pass and `/Applications/dock-switch.app` is replaced by the new build | Reinstall previous app bundle from backup or revert only the touched source files |
| Refresh Karabiner single-key launcher mapping | `yarn karabiner:f20` then `yarn karabiner:f20:check` | F3 opens SmartShadow directly; F6 opens ChatGPT directly; legacy left/right Shift mappings are removed so Shift stays default | Inspect `/Users/longbiao/.config/karabiner/karabiner.json` with `jq empty` and rerun the script |
| Place Computer Use browser beside Codex | `node scripts/place-computer-use-browser.js` | `Google Chrome` moves to the right half of the focused Codex display | Focus the intended Codex window and rerun; if stale, reset the Computer Use binding |

## Troubleshooting

| Trigger | Command | Expected Result | Failure Recovery |
| --- | --- | --- | --- |
| Hotkey does not move the visible window | Exercise the actual hotkey path, then compare with `dock-switch-cli` | Hotkey and CLI choose the same app/window/display | Inspect Karabiner mapping and launcher key routing before changing window-control code |
| Display placement is wrong | `node bin/dock-switch-cli.js displays` | Bounds match the physical screen layout | Update symbolic target mapping; do not hard-code stale coordinates |
| Installed app differs from source | Inspect `/Applications/dock-switch.app/Contents/Resources/app/` | Installed files match the intended repo build | Run `yarn dist` again and read back installed files |

## Verification

- CLI checks are supplementary. Completion requires the real hotkey, launcher, or visible app behavior to work.
- After app changes, run tests, run `yarn dist`, inspect the installed app, and exercise the actual desktop path.
- For Computer Use placement changes, verify the browser window lands on the intended display/right-half live.

## Release/Deploy

- Default flow is direct maintenance on `main` unless the user asks for another branch.
- "Ship it" means build/package/install the app, not just patch source.
- Keep README and docs aligned with the installed app behavior.

## Guardrails

- Prefer `AXUIElement`-based movement over AppleScript for normal window movement.
- Preserve reserved symbolic Codex display keys and ordinary HUD numeric fallbacks.
- Official Computer Use now targets the internal display by default; keep other standalone automation windows off the internal display unless the global guidance or current task explicitly says otherwise.

## Known State

- Use `node bin/dock-switch-cli.js displays` as the live display probe.
- Treat display labels as machine-specific runtime data; do not hard-code a maintainer's monitor names or local paths in public docs.

## Browser Automation Constraint
- Follow the global `~/.codex/AGENTS.md` browser/GUI routing. Keep only this project's URL, account, extension, fixture, viewport, and acceptance details here; do not promote Chrome or `chrome-use` to a project-wide default.
- Keep only repo-specific verification surfaces here; do not copy the full global policy block into this runbook.

## Development Workflow

- Follow the global `~/.codex/AGENTS.md` and workspace `/Users/longbiao/Documents/AGENTS.md` development workflow: work in the canonical checkout with one writer and do not create new worktrees.
- Use a task branch in the canonical checkout only when the task needs one; do not create manual worktree directories.
- Put reusable build caches and DerivedData in `~/Library/Caches/<project-id>/`, durable work products in `~/Local/<project-id>/`, and one-run scratch under `$TMPDIR`; pass output paths explicitly.
- Preserve existing dirty checkouts. Inspect `git status --short` before editing, and do not stash, commit, remove, migrate or clean user changes and pre-existing residue unless explicitly asked with an exact scope.
- Existing worktrees and other pre-existing noncompliant residue stay read-only unless the user explicitly requests an exact cleanup or migration scope.
