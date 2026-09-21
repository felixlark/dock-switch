GoKit5 Serial Control
=====================

``dock-switch`` can optionally listen to a connected GoKit5 / 机智云 controller over serial and convert host-button events into pointer display-selection and window activation actions.

Behavior
--------

- The serial listener starts automatically when dock-switch launches.
- Set ``DOCK_SWITCH_GOKIT5=0`` to disable serial listening.
- Set ``GOKIT5_SERIAL_PORT=/dev/cu.usbmodem...`` to pin the port when auto-detection is not reliable.
- ``dock-switch-cli gokit5-status`` reports whether the listener is enabled/running and which port it is using.

Button mapping
--------------

The firmware sends host-button events that move the pointer to display targets and click the target point:

- ``minus`` -> left side display center
- ``plus`` -> internal display center
- ``voice`` -> external display center
- ``green`` -> right side display center
- ``switch`` -> right side display center

GoKit5 events move the pointer, click the selected display center to activate the window at that point, and show the mouse feedback ripple. They do not launch, create, or move application windows. If a requested external or side display is not connected, dock-switch falls back to the internal main display work area.

Firmware
--------

The matching firmware is published at ``https://github.com/felixlark/open-embodied``.
