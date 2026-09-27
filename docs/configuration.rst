Configuration
=============

Config File
-----------

The app reads mapping data from:

- ``src/config.json``

Structure
---------

The top-level key is ``dock_items``, each containing:

- ``name``: app name expected from Dock metadata
- ``key``: keyboard key used to trigger app focus/launch
- ``screen``: display target used by settings rows and placement editing
- ``remember_window_state`` (optional): defaults to ``true``; when enabled, dock-switch restores last known window bounds for that app (in-memory for current app session)
- ``placement`` (optional): explicit placement policy (for example ``external_right_half`` or ``internal_fill``)
- ``kind`` (optional): built-in launch behavior tag. ``web_app`` defaults to ``internal_fill`` unless ``placement`` overrides it.
- ``open_path`` (optional): exact app bundle path to open instead of resolving by app name
- ``app_url`` (optional): exact Chrome ``--app=...`` URL used to identify a web app window by pid after launch

Notes
-----

- App names are matched exactly against Dock item names.
- Key matching in the renderer is case-insensitive, with symbolic support for launcher keys such as ``left_shift``, ``right_shift``, left ``Command``, right ``Command``, and ``Space``.
- In the current default config, Safari, Feishu, WeChat, Google Chrome, Calendar, Notes, Contacts, Mail, Sublime Text, and configured web apps are mapped to ``internal_fill`` on the internal display.
- In the current launcher behavior, ``F20`` opens the launcher, then ``left_shift`` opens ``Codex`` with ``external_fill``, ``right_shift`` opens ``Claude`` with ``external_fill``, left ``Command`` opens ``System Settings`` with ``internal_fill``, ``\`` opens ``Terminal`` with ``side_right_fill``, and right ``Command`` is a reserved no-op. ``F3`` and ``F6`` are local Karabiner exceptions: they open ``SmartShadow`` and ``ChatGPT`` directly, then use dock-switch placement with ``side_left_fill`` and ``side_right_fill``.
- Karabiner single-key shortcuts for ``F3`` and ``F6`` should be generated with ``yarn karabiner:f20``. The rule keeps ``F3`` direct for SmartShadow and ``F6`` direct for ChatGPT, while removing legacy ``left_shift`` and ``right_shift`` launcher mappings so Shift returns to the default system behavior.
- ``Codex``, ``ChatGPT``, ``SmartShadow``, ``Claude``, and Command shortcuts render in the launcher HUD as default Dock labels: ``L⇧`` for left Shift / Codex, ``F6`` for ChatGPT, ``F3`` for SmartShadow, ``R⇧`` for right Shift / Claude, and ``⌘`` for left/right ``Command``. The app defaults are configurable in Dock Switch Settings while remaining excluded from ordinary fallback numbering.
- Dock Switch Settings records shortcuts by keypress: click an app's shortcut cell, then press the key. Pressing and releasing left or right ``Shift`` (or ``Command``) on its own records ``L⇧``/``R⇧`` (``⌘``) and saves ``LEFT_SHIFT``/``RIGHT_SHIFT`` (``COMMAND_LEFT``/``COMMAND_RIGHT``). ``Delete`` clears the shortcut and ``Esc`` cancels. Keys the launcher uses itself (``F20``, arrows, ``[``/``]``, ``Return``) are rejected.
- A saved launcher key takes precedence over the built-in default app for that key, so assigning ``R⇧`` to ChatGPT opens ChatGPT instead of Claude.
- ``ArrowLeft`` moves the frontmost window to the left side-display work area.
- ``ArrowRight`` moves the frontmost window to the right side-display work area.
- ``ArrowUp`` moves the frontmost window to the external display work area.
- ``ArrowDown`` moves the frontmost window to the internal display work area.
- Arrow display moves also move the pointer to the center of the target display.
- ``【`` / ``】`` tile the frontmost window to the left or right half of its current display.
- ``1`` / ``2`` / ``3`` are available again for ordinary launcher item selection when those keys are assigned or used as fallback numbers.
- ``\`` is available as an ordinary launcher key and is assigned to ``Terminal`` in the default config.
- Screen direction codes used by keyboard movement are: ``0=external``, ``1=internal``, ``2=full``, ``3=left``, ``4=right``.
- If ``placement`` is set, placement behavior takes precedence over remembered bounds.
- App activation shortcuts move the pointer to the center of the activated or placed window.
- If ``kind`` is ``web_app`` and ``placement`` is not set, dock-switch places the app at ``internal_fill``.
- If ``open_path`` is set, dock-switch launches that exact app bundle.
- If ``app_url`` is set, dock-switch can place a Chrome app window by pid even when Accessibility exposes it as ``Google Chrome``.
- ``external_fill`` maximizes to the primary external display work area. With multiple external displays, this is the largest external display.
- ``side_left_fill`` maximizes to the left side-display work area.
- ``side_right_fill`` maximizes to the right side-display work area.
- If a requested external or side display is not connected, ``external_fill``, ``side_left_fill``, and ``side_right_fill`` fall back to the internal main display work area.
- GoKit5 host-button events move the pointer across displays and click the selected point to activate the window there: ``minus`` -> left side, ``plus`` -> internal, ``voice`` -> external, and ``green``/``switch`` -> right side. They do not launch, create, or move app windows.
- Holding ``Command`` changes those GoKit5 buttons into phrase-input keys: ``voice`` inserts ``/goal``, ``plus`` inserts ``/plan``, ``green``/``switch`` inserts ``side chat``, and ``minus`` inserts ``continue``. The phrase is inserted at the current caret without checking the foreground app and without pressing Return.
- If no external display is available, ``external_left_half`` falls back to the left half of the internal display work area.
- If no external display is available, ``external_right_half`` falls back to the right half of the internal display work area.

CLI and GoKit5
--------------

See :doc:`cli` for the command-line interface and :doc:`gokit5` for serial-button control.
