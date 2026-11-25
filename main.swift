// rhyper — make the physical Right Command key a dedicated Hyper modifier.
//
//   Hyper = Control + Option + Shift + Command
//
// Behaviour
//   * Right Command's own flagsChanged events are dropped, so apps never see
//     a Command press from that key. Tapping it alone does nothing.
//   * keyDown/keyUp events generated while it is held carry all four Hyper
//     flags (generic masks plus left-side device bits, i.e. they look exactly
//     like a real Ctrl+Opt+Shift+Cmd chord typed on the left of the keyboard).
//   * Every other observed event (other modifiers' flagsChanged, mouse
//     buttons/drags) has Right Command stripped, so Right Command never leaks
//     out as a plain Command (e.g. no accidental ⌘-click).
//
// Design notes (reliability)
//   * Stateless: "is Right Command held?" is read from the device-dependent
//     NX_DEVICERCMDKEYMASK bit that the HID system stamps on every event. The
//     HID system tracks the physical key even though we drop its
//     flagsChanged event. There is no boolean that can get out of sync, so a
//     missed release (tap timed out, process restarted) cannot leave Hyper
//     stuck.
//   * No synthetic events are ever posted; we only rewrite events in flight.
//     If rhyper dies, nothing is left half-pressed.
//   * The tap sits at the HID level (upstream of every session-level tap).
//     skhd installs its own head-inserted *session* tap; a session tap here
//     could end up downstream of skhd depending on start order, and skhd
//     would see plain Command instead of Hyper.
//   * The callback does only bit arithmetic. If macOS disables the tap
//     (timeout or user input), it is re-enabled immediately.
//
// Known limitations
//   * Secure Event Input (password fields, Terminal/iTerm "Secure Keyboard
//     Entry", some password managers): macOS does not deliver key events to
//     event taps, so Hyper is not applied and Right Command acts like a
//     normal Command key until secure input ends.
//   * Events are rewritten in place; anything that reads raw HID state
//     (IOHIDManager, CGEventSourceFlagsState(.hidSystemState)) still sees a
//     physical Right Command.
//   * Hyper is applied to key events only. Other modifiers' flagsChanged and
//     mouse events get Right Command stripped, not Hyper added. mouseMoved and
//     scrollWheel are not tapped (to keep pointer latency low), so they may
//     still carry a Command flag while Right Command is held.
//   * Hyper+. (Ctrl+Opt+Shift+Cmd+Period) is the system sysdiagnose shortcut.
//   * Accessibility permission is tied to the binary's code signature;
//     after rebuilding/reinstalling, re-grant it (remove and re-add).

import ApplicationServices
import Carbon.HIToolbox
import Foundation

let version = "0.1.0"

// MARK: - Flag arithmetic

/// Device-dependent modifier bits from IOKit's IOLLEvent.h (NX_DEVICE*KEYMASK).
/// CGEventFlags only names the device-independent masks.
enum DeviceFlag {
    static let leftControl: UInt64 = 0x0000_0001
    static let leftShift: UInt64 = 0x0000_0002
    static let leftCommand: UInt64 = 0x0000_0008
    static let rightCommand: UInt64 = 0x0000_0010
    static let leftOption: UInt64 = 0x0000_0020
}

enum Hyper {
    static let mask: UInt64 =
        CGEventFlags([.maskControl, .maskAlternate, .maskShift, .maskCommand]).rawValue
        | DeviceFlag.leftControl | DeviceFlag.leftOption
        | DeviceFlag.leftShift | DeviceFlag.leftCommand

    static func isRightCommandDown(_ flags: CGEventFlags) -> Bool {
        flags.rawValue & DeviceFlag.rightCommand != 0
    }

    /// Remove Right Command; keep generic Command only if Left Command is down.
    static func strippingRightCommand(_ flags: CGEventFlags) -> CGEventFlags {
        var raw = flags.rawValue & ~DeviceFlag.rightCommand
        if raw & DeviceFlag.leftCommand == 0 {
            raw &= ~CGEventFlags.maskCommand.rawValue
        }
        return CGEventFlags(rawValue: raw)
    }

    static func applying(to flags: CGEventFlags) -> CGEventFlags {
        CGEventFlags(rawValue: strippingRightCommand(flags).rawValue | mask)
    }
}

// MARK: - Logging (stderr; captured by launchd's StandardErrorPath)

func log(_ message: String) {
    let line = "\(Date().formatted(.iso8601)) rhyper: \(message)\n"
    FileHandle.standardError.write(Data(line.utf8))
}

// MARK: - Event tap

final class HyperTap {
    private var port: CFMachPort?

    private static let observedTypes: [CGEventType] = [
        .keyDown, .keyUp, .flagsChanged,
        .leftMouseDown, .leftMouseUp, .leftMouseDragged,
        .rightMouseDown, .rightMouseUp, .rightMouseDragged,
        .otherMouseDown, .otherMouseUp, .otherMouseDragged,
    ]

    func start() -> Bool {
        let mask = Self.observedTypes.reduce(CGEventMask(0)) { $0 | (1 << $1.rawValue) }

        guard let port = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, event, userInfo in
                // `self` outlives the run loop, so an unretained reference is safe.
                let tap = Unmanaged<HyperTap>.fromOpaque(userInfo!).takeUnretainedValue()
                return tap.handle(type: type, event: event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            log("failed to create event tap (is Accessibility permission granted?)")
            return false
        }
        self.port = port

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)
        return true
    }

    /// Hot path: bit arithmetic only. The event is modified in place and
    /// returned unretained (returning passRetained here would leak every event).
    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let port { CGEvent.tapEnable(tap: port, enable: true) }
            log("event tap was disabled (\(type == .tapDisabledByTimeout ? "timeout" : "user input")); re-enabled")
            return Unmanaged.passUnretained(event)

        case .flagsChanged
            where event.getIntegerValueField(.keyboardEventKeycode) == Int64(kVK_RightCommand):
            return nil  // Swallow the physical Right Command press/release.

        case .keyDown, .keyUp:
            if Hyper.isRightCommandDown(event.flags) {
                event.flags = Hyper.applying(to: event.flags)
            }

        default:
            if Hyper.isRightCommandDown(event.flags) {
                event.flags = Hyper.strippingRightCommand(event.flags)
            }
        }
        return Unmanaged.passUnretained(event)
    }
}

// MARK: - Startup

/// Prompts once, then waits until the user grants Accessibility, so launchd
/// does not respawn us (and re-prompt) in a loop.
func waitForAccessibility() {
    // Value of kAXTrustedCheckOptionPrompt; the C global is not concurrency-safe in Swift 6.
    let prompt = "AXTrustedCheckOptionPrompt"
    if AXIsProcessTrustedWithOptions([prompt: true] as CFDictionary) { return }

    log("""
        Accessibility permission required. Grant it under
          System Settings → Privacy & Security → Accessibility
        to the app that launched rhyper: your terminal when run from a shell,
        or \(CommandLine.arguments[0]) itself when run by launchd.
        Waiting for permission...
        """)
    while !AXIsProcessTrusted() { sleep(2) }
    log("Accessibility permission granted")
}

log("rhyper \(version) starting (pid \(getpid()))")
waitForAccessibility()

let hyperTap = HyperTap()
guard hyperTap.start() else { exit(1) }

if IsSecureEventInputEnabled() {
    log("warning: Secure Event Input is currently enabled by some app; Hyper will not apply until it is released")
}
log("running: Right Command → Hyper (⌃⌥⇧⌘)")
CFRunLoopRun()
