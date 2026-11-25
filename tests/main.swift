// Unit tests for Hyper.decide. Built with Hyper.swift by `make test`;
// plain assertions, no XCTest/SwiftPM, so it runs with just the CLT.

import Carbon.HIToolbox
import CoreGraphics
import Foundation

// MARK: - Fixtures (raw flag values as the HID system produces them)

let cmd = CGEventFlags.maskCommand.rawValue
let shift = CGEventFlags.maskShift.rawValue
let capsLock = CGEventFlags.maskAlphaShift.rawValue
let fn = CGEventFlags.maskSecondaryFn.rawValue
let numPad = CGEventFlags.maskNumericPad.rawValue
let nonCoalesced = CGEventFlags.maskNonCoalesced.rawValue

let rightCmd = cmd | DeviceFlag.rightCommand
let leftCmd = cmd | DeviceFlag.leftCommand
let bothCmd = cmd | DeviceFlag.leftCommand | DeviceFlag.rightCommand
let leftShift = shift | DeviceFlag.leftShift
let rightShift = shift | DeviceFlag.rightShift

/// Exactly what a physical left-hand Ctrl+Opt+Shift+Cmd chord produces.
let hyper: UInt64 = 0x001E_0000 | 0x01 | 0x02 | 0x08 | 0x20

let keyH = Int64(kVK_ANSI_H)
let keyRightCmd = Int64(kVK_RightCommand)
let keyLeftCmd = Int64(kVK_Command)
let keyLeftShift = Int64(kVK_Shift)

let mouseTypes: [CGEventType] = [
    .leftMouseDown, .leftMouseUp, .leftMouseDragged,
    .rightMouseDown, .rightMouseUp, .rightMouseDragged,
    .otherMouseDown, .otherMouseUp, .otherMouseDragged,
]

// MARK: - Harness

nonisolated(unsafe) var failures = 0
nonisolated(unsafe) var checks = 0

func describe(_ d: Hyper.Decision) -> String {
    switch d {
    case .drop: "drop"
    case .pass: "pass"
    case .rewrite(let f): "rewrite(0x\(String(f.rawValue, radix: 16)))"
    }
}

func expect(
    _ name: String, _ type: CGEventType, key: Int64 = 0, flags: UInt64,
    _ expected: Hyper.Decision, line: Int = #line
) {
    checks += 1
    let actual = Hyper.decide(type: type, keyCode: key, flags: CGEventFlags(rawValue: flags))
    if actual != expected {
        failures += 1
        print("FAIL [line \(line)] \(name): expected \(describe(expected)), got \(describe(actual))")
    }
}

func rewrite(_ raw: UInt64) -> Hyper.Decision { .rewrite(CGEventFlags(rawValue: raw)) }

// MARK: - Constants

checks += 1
if Hyper.mask != hyper {
    failures += 1
    print("FAIL Hyper.mask = 0x\(String(Hyper.mask, radix: 16)), expected 0x\(String(hyper, radix: 16))")
}

// MARK: - Right Command itself is swallowed

expect("RCmd press", .flagsChanged, key: keyRightCmd, flags: rightCmd | nonCoalesced, .drop)
expect("RCmd release", .flagsChanged, key: keyRightCmd, flags: nonCoalesced, .drop)
expect("RCmd release, LCmd still held", .flagsChanged, key: keyRightCmd, flags: leftCmd, .drop)
expect("RCmd press, LCmd held", .flagsChanged, key: keyRightCmd, flags: bothCmd, .drop)

// MARK: - Keys while Right Command is held get exactly Hyper

for type in [CGEventType.keyDown, .keyUp] {
    expect("RCmd+H \(type)", type, key: keyH, flags: rightCmd, rewrite(hyper))
    expect("RCmd+H non-coalesced \(type)", type, key: keyH, flags: rightCmd | nonCoalesced,
           rewrite(hyper | nonCoalesced))
}
expect("RCmd+H keeps caps lock", .keyDown, key: keyH, flags: rightCmd | capsLock, rewrite(hyper | capsLock))
expect("RCmd+arrow keeps fn/numpad", .keyDown, key: Int64(kVK_LeftArrow),
       flags: rightCmd | fn | numPad, rewrite(hyper | fn | numPad))
expect("RCmd+RShift+H keeps right-shift bit", .keyDown, key: keyH,
       flags: rightCmd | rightShift, rewrite(hyper | DeviceFlag.rightShift))
expect("LCmd+RCmd+H is Hyper", .keyDown, key: keyH, flags: bothCmd, rewrite(hyper))

// MARK: - Without Right Command nothing changes

expect("plain H", .keyDown, key: keyH, flags: nonCoalesced, .pass)
expect("LCmd+H", .keyDown, key: keyH, flags: leftCmd, .pass)
expect("LCmd+H up", .keyUp, key: keyH, flags: leftCmd, .pass)
expect("LCmd press", .flagsChanged, key: keyLeftCmd, flags: leftCmd, .pass)
expect("LCmd release", .flagsChanged, key: keyLeftCmd, flags: 0, .pass)
expect("synthetic cmd without device bits", .keyDown, key: keyH, flags: cmd, .pass)
expect("real hyper chord passes untouched", .keyDown, key: keyH, flags: hyper, .pass)
for type in mouseTypes {
    expect("LCmd \(type)", type, flags: leftCmd, .pass)
}

// MARK: - Other events while Right Command is held: Right Command stripped, no Hyper

expect("LShift press during RCmd", .flagsChanged, key: keyLeftShift,
       flags: rightCmd | leftShift, rewrite(leftShift))
expect("LShift release during RCmd", .flagsChanged, key: keyLeftShift, flags: rightCmd, rewrite(0))
expect("LCmd press during RCmd keeps cmd", .flagsChanged, key: keyLeftCmd, flags: bothCmd, rewrite(leftCmd))
expect("LCmd release during RCmd drops cmd", .flagsChanged, key: keyLeftCmd, flags: rightCmd, rewrite(0))
for type in mouseTypes {
    expect("RCmd \(type) becomes plain", type, flags: rightCmd, rewrite(0))
    expect("LCmd+RCmd \(type) stays LCmd", type, flags: bothCmd, rewrite(leftCmd))
}

// MARK: - Stuck-state scenario: hold both, release Right Command first

// After RCmd's release (dropped), HID flags carry only LCmd: everything passes.
expect("after RCmd release, LCmd+C is plain ⌘C", .keyDown, key: Int64(kVK_ANSI_C), flags: leftCmd, .pass)
expect("after RCmd release, click is ⌘-click", .leftMouseDown, flags: leftCmd, .pass)

// MARK: - Result

print(failures == 0 ? "OK: \(checks) checks passed" : "FAILED: \(failures) of \(checks) checks")
exit(failures == 0 ? 0 : 1)
