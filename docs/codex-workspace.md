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
ignored. Focused-window and focused-element notifications also trigger a rescan, covering
same-title navigation when the application exposes a focus notification. A 150 ms trailing
coalescing interval collapses duplicate notifications; this is a UI settling delay, not
a limit on tasks, windows, or events. A two-second maintenance timer checks preferences,
trust and process presence, without polling the AX tree. There are no new resource caps.

A recognized snapshot requires a standard focused window with no native sheet and an
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

## Verification record

- Baseline: 102 Node tests, 43 Swift tests passed.
- Candidate: `yarn test` passes 102 Node and 57 Swift tests. Added tests cover duplicate
  events, open-pane idempotence, manual close, opaque identity vs rename/same-name cases,
  window transitions, restart baseline, and first open after starting outside a chat.
  Failure-injection tests cover unreadable tabs roles/ancestor children, subscription
  retry after transient AX failure, unsupported notifications, stale subscription release,
  the unnamed AXButton wrappers around Codex header controls, and nested toolbar ancestor
  groups/shell-boundary/cycle handling.
  Unknown reads suppress actions; only a complete scan can prove tabs absent. Lifecycle
  maintenance retries transient subscription failures without restarting Codex; diagnostics
  distinguish active, unsupported and retryable subscription counts.
  These are state-policy/AX adapter tests, not GUI evidence for AX object stability.
- Signed native build/install: performed using the existing Developer ID identity and
  installed launcher configuration. The previous installed bundle/config is retained
  outside the repository. Installation and policy verification are separate from acceptance.
- Official Computer Use opened the installed settings app, toggled off/on, and runtime
  status confirmed detachment/reattachment with existing Accessibility trust.
- Earlier in this integration session, the official Open Computer Use tool visibly
  showed chat headers, Chat tabs and New tab, and manually hid the workspace. This did
  not prove the automatic action on the final candidate.
- Subsequent official unified Computer Use returned: `Computer Use is not allowed to
  use the app 'com.openai.codex' for safety reasons.` No alternative GUI controller was
  used against Codex after this explicit denial. No asar or TCC modification was made.

## OCU continuation

The user subsequently specified Open Computer Use (OCU) for Codex itself. OCU successfully
read and interacted with Codex; the earlier unified CUA refusal does not describe OCU's
current capability. No security policy or macOS permission was changed.

Live OCU acceptance exposed a real failure in b0cae31: the pane stayed closed after a
round trip and the runtime recorded events but zero presses. The rendered AX tree flattened
several unnamed ancestors. The true toolbar parent contained only the toolbar, so searching
only that immediate parent could never find the workspace controls. The adapter now climbs
to the nearest AXGroup with recognized controls; it stops at an unknown read, parent cycle,
or non-group shell boundary rather than searching arbitrary app content. Added tests cover
these actual wrapper relationships and boundaries.

On the repaired installed code, OCU hid the workspace, switched to another existing chat,
and switched back. The workspace visibly reopened and runtime AXPress returned success.
Four further switches between the same two open chats retained one tab per chat and left
pressCount unchanged. Screenshots and read-only counters are retained in the local issue49
log/evidence directory. Cmd+T was also visibly verified as New tab (URL entry focused), not
New Page, during the OCU continuation.

The PR remains Draft and is not merged. Remaining extended GUI cases and the final
candidate-bound review/readback are tracked in the original Issue/PR; tests of opaque
identity do not alone prove rename/same-name stability on future Codex versions. A live
Codex restart must preserve other active chats rather than interrupt them merely to obtain
a test result. The adapter's on/off lifecycle can be tested without restarting Codex.
