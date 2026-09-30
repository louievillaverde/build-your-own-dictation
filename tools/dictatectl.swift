import Foundation
let n = CommandLine.arguments.dropFirst().first ?? "start"
DistributedNotificationCenter.default().postNotificationName(.init("com.example.dictation.\(n)"), object: nil, userInfo: nil, deliverImmediately: true)
