# Changelog

## [0.1.0] - 2026-11-25

- Right Command acts as a dedicated Hyper modifier (Ctrl+Opt+Shift+Cmd) via a
  HID-level CGEventTap; Right Command alone does nothing.
- Stateless remapping derived from device-dependent modifier bits, so a missed
  key release cannot leave Hyper stuck.
- Event tap is re-enabled automatically after a timeout or user-input disable.
- Waits for Accessibility permission instead of exiting.
- Makefile (GNU Make 3.81 / BSD make compatible) with build, test, install and
  LaunchAgent (`nl.mtak.rhyper`) targets.
- Dependency-free unit tests (`make test`).
