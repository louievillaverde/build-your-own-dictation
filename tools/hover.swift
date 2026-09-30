import CoreGraphics
import Foundation
// Moves the pointer to (x, y) in top-left screen points via real mouse-moved events.
let a = CommandLine.arguments
let to = CGPoint(x: Double(a[1])!, y: Double(a[2])!)
let from = CGEvent(source: nil)!.location
for i in 1...12 {
    let t = Double(i) / 12
    let p = CGPoint(x: from.x + (to.x - from.x) * t, y: from.y + (to.y - from.y) * t)
    CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: p, mouseButton: .left)!.post(tap: .cghidEventTap)
    Thread.sleep(forTimeInterval: 0.015)
}
