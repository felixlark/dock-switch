# Codex workspace adapter

Refs: [dock-switch #49](https://github.com/felixlark/dock-switch/issues/49),
[qiming-dynasty/Development #20](https://github.com/qiming-dynasty/Development/issues/20).

## Requirements and integration decision

The requested outcome is to reopen the workspace after a recognized chat/window switch,
only if it is closed. Cmd+T remains New tab. This adapter does not implement New Page.

Use Apple's public AXObserver in the existing native runtime, rather than a separate
resident process or a change to Codex. The existing Accessibility authorization gates
both subscription and action. The settings app shares the runtime's preference domain;
the runtime uses standard defaults for its own bundle ID, avoiding Foundation's invalid
self-suite assertion. Preferences are outside the signed bundle.

A top-level AXTitleChanged notification is only a rescan signal. Child title noise is
ignored. Focused-window and focused-element notifications also trigger a rescan. Public
AXValueChanged from only the primary shell AXWebArea (`app://-/index.html`) also triggers
one: live OCU proved Codex emits it for dialog mount/unmount without a native focus event.
No AXValue is read; body/input events and nested web areas are rejected. A shell event
synchronously checks only for dialogs and invalidates the old baseline on a dialog or
unknown read, before coalescing. A subsequent clear event cannot erase this invalidation,
even when mount and dismissal occur before the delayed action callback. A 150 ms trailing
coalescing interval collapses duplicate notifications; this is a UI settling delay, not
a limit on tasks, windows, or events. A two-second maintenance timer checks preferences,
trust and process presence, without polling the AX tree. There are no new resource caps.

A recognized snapshot requires a standard focused window with no native sheet or public dialog and an
English `Chat toolbar` in the app shell's public AX web area (`app://-/index.html`).
The scan excludes conversation/composer, sidebar lists, and nested browser web areas.
`Chat tabs` means open. With that group absent, an enabled header `New tab` button is
the only allowed action. An unknown state does nothing. This may create one blank tab
when reopening, because that is the public action the installed product exposes.

The mounted toolbar's opaque AX identity, together with its window, is the view identity.
Titles are not compared or logged. An unchanged view never reopens after a manual close.
Before AXPress, the window, view, button, closed state, preference and trust are read
again. No global key event or activation is sent. A failed/unknown press is not replayed.
Settings and unsupported layouts do not update the recognized-view baseline. On initial
attachment, an existing chat is seeded without opening; attachment outside a chat allows
the first subsequently opened chat to expand.

## Compatibility and rollback

Target observed during integration: installed Codex 26.1023.51421, `com.openai.codex`.
AX view identity and notifications are application behavior, not a documented task API.
If Codex remounts the same chat toolbar, omits a same-name switch notification, changes
labels, or changes its shell structure, this adapter needs revalidation. Full view without
a chat toolbar and archived-chat pages are intentionally unsupported. Disable the switch
in dock-switch Settings to detach; quit also removes subscriptions and timers. Codex exit
and loss of existing authorization detach the observer; process restart/authorization
restoration reattach without prompting. A future native always-open workspace option is
the retirement condition for this adapter.

The existing launcher and GoKit5 lifecycle remains in the same app. Read-only diagnostics
are available through `node scripts/codex-workspace-status.js`. Counts and errors contain
no chat titles or bodies.

## Candidate-bound verification

Code candidate: `4c4b4bacaca7b55e7b8e3c7e8e495c750d1c5c6e`, based on
`dbe4eef56f6f10ce178399be83d9ec250dc18230`. Documentation updates retain the same
runtime source files and installed binary. Baseline tests: 102 Node / 43 Swift.
Final `yarn test`: 102 Node / 61 Swift, all passed. Tests cover unreadable AX data,
subscription retry/release, header ancestor boundaries, shell signal filtering, startup,
manual close, same-name/window identity, and modal invalidation before deferred actions.

The existing Developer ID build/install pipeline produced the installed native app.
Built and installed Mach-O UUIDs match (`76FF3A2B-89B5-3BB7-909B-7BE61BAF8B85`);
`codesign --verify --deep --strict` passes with team `HJG65XBC25`. The installed launcher
configuration matches its pre-change backup. No Codex asar, TCC state or private database
was changed; no other product was merged or deployed.

Official Open Computer Use (`mcp__open_computer_use`) visibly exercised installed Codex
26.1023.51421 and installed dock-switch Settings on the same code candidate:

| Interaction | Observed result |
| --- | --- |
| Manually hide workspace in the same chat | Remained closed; no automatic press |
| Switch away and back to a closed workspace | One visible New tab; AXPress success |
| Four switches between already-open chats | Each retained one tab; pressCount stayed 9 |
| Rename Cancel / Save / restore original title while closed | Remained closed; no automatic press; baseline seeded before subsequent navigation |
| Two existing chats temporarily sharing the same title | Both closed targets reopened on real switches; titles were not used as identity |
| Cmd+T | One additional New tab; URL field focused; test tab then removed |
| Disable setting, close pane, switch away/back | Subscriptions detached to zero; pane stayed closed |
| Re-enable while a chat is closed | Seeded the current closed chat without opening; subsequent navigation to another closed chat reopened that target |
| Open same chat in another window, manually close its pane, focus original then return | Closed second-window pane reopened once; original retained one tab |
| Close test-created window | Returned to original window; subscriptions returned from seven to six |

The rename tests observed the primary shell value-change signals and successful
post-dialog seeding. The targeted dialog destroyed subscription registered, but its
callback counter remained zero in this run; recovery was proved through shell signals,
not assumed destroyed delivery. Final runtime: enabled/observing/trusted, six active
subscriptions, no unsupported or retryable registrations. The Settings window and test
window were closed; the original chat title and a single open workspace tab were left.
Screenshots, status readbacks and historical failures remain in the local issue49 evidence
log. They are not uploaded with private chat contents to the public repository.

Independent read-only reviewer `/root/independent_review` reviewed the overall change
from the integration baseline and supplemented every code revision through the code
candidate above. The two initial P2 findings (unknown-read handling and subscription
recovery) and the later P2 (debounce swallowing a transient dialog) were fixed and cleared.
The reviewer independently reran all 102 Node / 61 Swift tests and found no remaining
code blocker. Exact reviewer model ID and reasoning setting were not exposed.

Codex itself was not restarted while other chats were active, and Accessibility permission
was not revoked for testing. Startup/restart policy tests and live on/off attachment are
separate from an unperformed live host-restart or TCC-revocation test. AX identity and event
delivery remain compatibility assumptions: if the server delivers a notification only
after a transient dialog disappears, public snapshots cannot reconstruct its past structure.
Do not infer future-version or all-timing guarantees from the tested interactions.

PR #50 links both original issues and is not merged. The previous installed app is retained
for rollback; disabling the setting is the immediate runtime rollback.
