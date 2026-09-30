import CoreGraphics
import Foundation
let a = CommandLine.arguments.dropFirst().map { Double($0)! }
let from = CGPoint(x: a[0], y: a[1]), to = CGPoint(x: a[2], y: a[3])
func post(_ t: CGEventType, _ p: CGPoint) { CGEvent(mouseEventSource: nil, mouseType: t, mouseCursorPosition: p, mouseButton: .left)!.post(tap: .cghidEventTap) }
post(.mouseMoved, from); Thread.sleep(forTimeInterval: 0.5)
post(.leftMouseDown, from); Thread.sleep(forTimeInterval: 0.1)
for i in 1...30 { let t = Double(i)/30; post(.leftMouseDragged, CGPoint(x: from.x+(to.x-from.x)*t, y: from.y+(to.y-from.y)*t)); Thread.sleep(forTimeInterval: 0.02) }
post(.leftMouseUp, to)
