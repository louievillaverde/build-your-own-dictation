import CoreGraphics
import Foundation
// Simulates holding right Option for 1.2s (keycode 61, alternate + right-alt device bit).
let src = CGEventSource(stateID: .hidSystemState)
let down = CGEvent(keyboardEventSource: src, virtualKey: 61, keyDown: true)!
down.type = .flagsChanged; down.flags = CGEventFlags(rawValue: 0x80000 | 0x40)
down.post(tap: .cghidEventTap)
Thread.sleep(forTimeInterval: 0.1)
let up = CGEvent(keyboardEventSource: src, virtualKey: 61, keyDown: false)!
up.type = .flagsChanged; up.flags = CGEventFlags(rawValue: 0)
up.post(tap: .cghidEventTap)
