CLI
===

``dock-switch-cli`` is the canonical command-line entrypoint for window placement, display inspection, and pid/profile-bound Chrome targeting.

Examples
--------

.. code-block:: bash

   dock-switch-cli displays
   dock-switch-cli gokit5-status
   dock-switch-cli codex-display --target side_right
   dock-switch-cli place --app "SmartShadow" --placement external_fill
   dock-switch-cli place --app "Terminal" --placement side_right_fill
   dock-switch-cli place --pid 12345 --placement external_right_half
   dock-switch-cli move --app "Terminal" --x 0 --y 25 --w 1512 --h 875
   dock-switch-cli move --pid 12345 --x 0 --y 25 --w 1512 --h 875

If ``dock-switch-cli`` is not on your PATH, run it from this repo as ``node bin/dock-switch-cli.js ...``.

Managed Chrome Windows
----------------------

Codex browser work should use the official Chrome plugin for signed-in Google Chrome state and the in-app browser for unauthenticated local or public pages. The profile-bound Chrome CLI helpers are retained only for lower-level window placement.

.. code-block:: bash

   dock-switch-cli displays
   dock-switch-cli get-chrome-window --profile-dir /tmp/chrome_profile-XXXXXX
   dock-switch-cli move-chrome-window --profile-dir /tmp/chrome_profile-XXXXXX --x 713 --y -1410 --w 1280 --h 1410

Notes
-----

- Use ``--pid`` when you need to target one managed window from a multi-window app such as Google Chrome.
- Use the Chrome profile commands only for lower-level profile-bound Chrome placement; normal Codex browser work should go through the official Chrome plugin or the in-app browser.
- If the dock-switch control socket is unavailable, the CLI launches ``/Applications/dock-switch.app`` and retries automatically.
- ``codex-display`` focuses an existing Codex window on the target display when available. If no Codex window exists on that display, it creates one there without moving windows from other displays. It always centers the pointer on the target display work area so repeated physical key presses do not drift with window bounds. If a requested external target is offline, Codex display selection falls back to the internal main display.
