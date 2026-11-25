// Pure remapping logic: no I/O, no event objects, unit-tested by tests/main.swift.

import CoreGraphics
import Carbon.HIToolbox

/// Device-dependent modifier bits from IOKit's IOLLEvent.h (NX_DEVICE*KEYMASK).
/// CGEventFlags only names the device-independent masks.
enum DeviceFlag {
    static let leftControl: UInt64 = 0x0000_0001
    static let leftShift: UInt64 = 0x0000_0002
    static let rightShift: UInt64 = 0x0000_0004
    static let leftCommand: UInt64 = 0x0000_0008
    static let rightCommand: UInt64 = 0x0000_0010
    static let leftOption: UInt64 = 0x0000_0020
}

enum Hyper {
    /// What the event tap should do with an event.
    enum Decision: Equatable {
        case drop
        case pass
        case rewrite(CGEventFlags)
    }

    static let mask: UInt64 =
        CGEventFlags([.maskControl, .maskAlternate, .maskShift, .maskCommand]).rawValue
        | DeviceFlag.leftControl | DeviceFlag.leftOption
        | DeviceFlag.leftShift | DeviceFlag.leftCommand

    static func decide(type: CGEventType, keyCode: Int64, flags: CGEventFlags) -> Decision {
        if type == .flagsChanged && keyCode == Int64(kVK_RightCommand) {
            return .drop  // Swallow the physical Right Command press/release.
        }
        guard isRightCommandDown(flags) else { return .pass }

        switch type {
        case .keyDown, .keyUp:
            return .rewrite(applying(to: flags))
        default:
            return .rewrite(strippingRightCommand(flags))
        }
    }

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
