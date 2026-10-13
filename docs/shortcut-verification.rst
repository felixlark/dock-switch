Shortcut Verification
=====================

Design contract
---------------

This verifies the existing contract in :doc:`configuration` and README:
Caps Lock switches the macOS input source, a lone right Command sends F20 to
toggle the HUD, and Command chords keep their modifier behavior. It adds no
launcher behavior or persistent monitoring service.

Bounded state recording
-----------------------

Run from the canonical checkout on macOS with the installed app running:

.. code-block:: bash

   node scripts/record-shortcut-verification.js \
     --output /absolute/path/to/new-shortcut-evidence.ndjson --duration 60

Wait for ``READY`` before exercising keys. Output creation is exclusive; an
existing evidence file is never overwritten. The observer compiles in temporary
storage, uses a module cache in ``~/Library/Caches/dock-switch/``, and exits after
1–300 seconds. Ctrl-C terminates the observer and records an interrupted exit.

The NDJSON binds the run to the Git candidate/dirty state, installed executable
hash, recorder hashes, and Karabiner config hash/check. It records changes in
the current input-source ID, installed HUD visibility/bounds, and frontmost
app bundle/window bounds at 100 ms intervals. It uses public TIS, NSWorkspace
and CGWindow APIs; it neither injects keys nor requests new permissions.
It records no text, key stream, window titles, credentials or screenshots.
Unavailable window observation is unknown, not a successful hidden-HUD result.
It is a state observer, not proof of the origin of a keyboard event.
HUD identification uses the installed process and the current 60pt overlay
strip geometry; it excludes the separate 132pt mouse-feedback window. Revisit
this filter if the overlay layout design changes.

Physical-key acceptance sequence
--------------------------------

1. Confirm ``yarn karabiner:f20:check`` is current and the macOS Caps Lock
   input-source option is enabled. Do not alter privacy permissions to record.
2. With the HUD closed, tap physical Caps Lock twice. Require alternating
   Chinese/U.S. input-source IDs and no HUD appearance.
3. Tap physical right Command twice. Require HUD show then hide, with no
   input-source change. Test direct F20 separately.
4. In a disposable, nonsensitive text field, exercise a right Command chord
   (for example Select All). Require the expected app action and no HUD toggle.
   Record the visible app action through official Computer Use; this observer
   cannot prove chord semantics by itself.
5. Continue the existing core flow: open the HUD, select an app using its shown
   key, require HUD dismissal, app activation, and configured window placement.
   Inspect the installed HUD and selected app through official Computer Use,
   and record the actual entry and step results in the receipt.

Keep the actions/timestamps alongside the trace. CLI
``show-launcher`` may prepare a visible HUD for a selection check, but it does
not establish F20 or Karabiner physical-key acceptance. Official Computer Use
may reject a lone modifier or bypass the physical Karabiner path; report that
gap without synthesizing input through another framework. Leave the HUD closed
and the installed app running after verification.

Delivery entry
--------------

For this native macOS utility, give the installed app path
``/Applications/dock-switch.app`` and the menu-bar entry ``Show Launcher`` in
the receipt. It requires no account login; macOS permissions are a separate
boundary. This utility has no hosted web UI. The public
`verification guide <https://github.com/felixlark/dock-switch/blob/main/docs/shortcut-verification.rst>`_
is an engineering artifact, not a replacement for the installed app or physical
keyboard acceptance.

When a result has an accessible system or page, provide its direct entry and
login instructions if needed. Do not record video or add screenshots as a
substitute for that entry. Preserve already collected evidence; do not delete it
as part of changing the delivery format. Screenshots for results without an
interface remain local evidence and must not be committed to this repository.

Next milestone
--------------

This repository currently has no separate PRD or future-feature roadmap.
The next acceptance milestone is the complete keyboard path defined in
``configuration.rst``: physical Caps Lock/right Command/chord verification,
then HUD shown-key selection, app activation and configured display placement.
This is validation of existing behavior, not authorization for new features.
