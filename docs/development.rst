Development
===========

Prerequisites
-------------

- macOS (the helper binary and behavior are macOS-specific)
- Node.js and Yarn
- Electron build tooling

Setup
-----

1. Install dependencies:

   .. code-block:: bash

      yarn install

2. Run the app locally:

   .. code-block:: bash

      yarn go

Build
-----

- Unsigned build:

  .. code-block:: bash

     yarn dist

- Signed build (requires valid signing identity):

  .. code-block:: bash

     yarn dist:signed

Tests
-----

Run the Node test suite:

.. code-block:: bash

   node --test test/*.test.js

Docs
----

Sphinx documentation sources live under ``docs/``.

.. code-block:: bash

   python -m pip install sphinx
   make -C docs html

Troubleshooting
---------------

- If the app does not respond to `F20`, verify your key remapping.
- If the single-key launchers stop working, run ``yarn karabiner:f20`` and then ``yarn karabiner:f20:check``. Karabiner should run the configured app cycle for ``F3`` and open Codex through SmartShadow for ``F6``; legacy left/right Shift launcher mappings should be removed so Shift returns to the default system behavior.
- If helper actions fail, re-check Accessibility/Privacy permissions.
- If the app does not relaunch after build scripts, close existing instances and retry.
