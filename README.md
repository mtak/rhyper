# rhyper

Turn the physical **Right Command** key into a dedicated **Hyper** modifier on
macOS:

    Hyper = Control + Option + Shift + Command

Hold Right Command and press `h`, and applications receive
`Ctrl+Opt+Shift+Cmd+H`. Works system-wide with tools that bind global
shortcuts, such as [skhd](https://github.com/koekeishiya/skhd)
(`hyper - h : ...`) and [Rectangle](https://rectangleapp.com). Right Command
on its own does nothing; Left Command is unaffected.

A small, dependency-free Swift utility using a Quartz event tap — no
Karabiner-Elements, no kernel or driver extensions.

## Version: 0.1.0

## Install

### Homebrew

```sh
brew tap mtak/tap
brew trust mtak/tap      # Homebrew 7+ refuses formulae from untrusted taps
brew install rhyper
brew services start rhyper
```

Then grant Accessibility to `/opt/homebrew/opt/rhyper/bin/rhyper`
(see [Permissions](#permissions)).

### From source

Requires the Xcode Command Line Tools (Swift 6).

```sh
make build        # → build/rhyper
make test         # unit tests
make install      # → ~/.local/bin/rhyper (override with PREFIX=...)
```

To run at login as a LaunchAgent (`nl.mtak.rhyper`, logs to
`~/Library/Logs/rhyper.log`):

```sh
make agent-install load
make restart                     # after reinstalling
make unload                      # stop
make agent-uninstall uninstall   # remove everything
```

Use either Homebrew services or the Makefile LaunchAgent, not both.

## Permissions

rhyper needs **Accessibility** permission
(System Settings → Privacy & Security → Accessibility). On first start it
prompts and waits until permission is granted. Input Monitoring is not
required.

Grant it to:

- **your terminal app** when running from a shell (`make run`), or
- **the rhyper binary** when running as a service:
  `/opt/homebrew/opt/rhyper/bin/rhyper` (Homebrew) or `~/.local/bin/rhyper`
  (Makefile). Press ⌘⇧G in the file picker to type the path.

The grant is tied to the binary's code signature. **After every upgrade or
reinstall, remove the entry, add it again**, and restart the service —
otherwise the toggle shows as enabled but the tap cannot be created.

## How it works

- Right Command's own modifier events are dropped, so apps never see a
  Command press from that key.
- Key down/up events typed while it is held get all four Hyper flags, exactly
  as a physical left-hand Ctrl+Opt+Shift+Cmd chord would produce.
- Other events (other modifiers, mouse clicks and drags) have Right Command
  stripped, so it never acts as a plain Command (e.g. no accidental ⌘-click).
- Whether Right Command is held is read from the device-dependent modifier
  bit on each event rather than tracked in state, so a missed key release
  can never leave Hyper stuck. rhyper never posts synthetic events; if it
  exits, nothing is left pressed.
- The tap sits at the HID level, upstream of session-level taps such as
  skhd's, so start order does not matter.
- If macOS disables the tap (timeout or user input), it is re-enabled
  immediately.

## Known limitations

- **Secure Input** (password fields, Terminal/iTerm "Secure Keyboard Entry",
  some password managers): macOS does not deliver key events to event taps, so
  Hyper is not applied and Right Command behaves like a normal Command key.
- Pointer movement and scroll events are not tapped (to keep pointer latency
  low) and may still carry a Command flag while Right Command is held.
- Software that reads raw HID state still sees a physical Right Command.
- **Hyper+.** is the macOS sysdiagnose shortcut; avoid binding it.

## License

[MIT](LICENSE)
