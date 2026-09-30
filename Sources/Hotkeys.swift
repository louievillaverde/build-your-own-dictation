import AppKit

/// Keys (the two modifier keys are chosen in Settings):
///   talk key   hold = push-to-talk into the cursor; double-tap = hands-free, tap again to finish
///   ⌃⌥F        tap = fix the selected text; hold = say how to change it, release to apply
///   Esc        cancel while recording
///   ⌃⌥V        paste the last dictation again
///   ⌃⌥H        open history
final class Hotkeys {
    enum Event { case startHold, startHandsFree, finish, cancel, pasteLast, history,
                 fixSelection, startFixInstruction }
    var handler: ((Event) -> Void)?
    var isRecording: () -> Bool = { false }
    var isHandsFree: () -> Bool = { false }

    private var tap: CFMachPort?
    private var downAt: Date?
    private var downKey: TalkKey?
    private var pendingStart: DispatchWorkItem?
    private var chorded = false
    private var startedByThisPress = false
    private var lastTap: Date = .distantPast
    private var fixDown: Date?
    private var fixHold: DispatchWorkItem?
    private var fixRecording = false

    func install() -> Bool {
        let mask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue) | (1 << CGEventType.flagsChanged.rawValue)
        let ref = Unmanaged.passUnretained(self).toOpaque()
        tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                eventsOfInterest: CGEventMask(mask), callback: { _, type, event, ref in
            let me = Unmanaged<Hotkeys>.fromOpaque(ref!).takeUnretainedValue()
            return me.handle(type, event)
        }, userInfo: ref)
        guard let tap else { return false }
        let src = CFMachPortCreateRunLoopSource(nil, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), src, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    private func emit(_ e: Event) { DispatchQueue.main.async { self.handler?(e) } }

    private func handle(_ type: CGEventType, _ event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }
        let code = event.getIntegerValueField(.keyboardEventKeycode)
        let f = event.flags
        let ctrlOpt = f.contains(.maskControl) && f.contains(.maskAlternate) && !f.contains(.maskCommand)

        if type == .keyUp {
            if code == 3, fixDown != nil {   // F released
                fixDown = nil
                fixHold?.cancel()
                if fixRecording { fixRecording = false; emit(.finish) } else { emit(.fixSelection) }
                return nil
            }
            return Unmanaged.passUnretained(event)
        }

        if type == .keyDown {
            let isRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
            if ctrlOpt {
                if code == 9 { if !isRepeat { emit(.pasteLast) }; return nil }   // V
                if code == 4 { if !isRepeat { emit(.history) }; return nil }     // H
                if code == 3 {                                                  // F
                    if !isRepeat && fixDown == nil {
                        fixDown = Date()
                        let w = DispatchWorkItem { [weak self] in
                            guard let self, self.fixDown != nil else { return }
                            self.fixRecording = true
                            self.handler?(.startFixInstruction)
                        }
                        fixHold = w
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: w)
                    }
                    return nil
                }
            }
            if code == 53 && isRecording() { emit(.cancel); return nil } // Esc
            // Another key while a modifier is down = the user is typing a shortcut, not talking.
            if downAt != nil {
                chorded = true
                pendingStart?.cancel()
                if startedByThisPress, let d = downAt, Date().timeIntervalSince(d) < 0.6 { emit(.cancel) }
            }
            return Unmanaged.passUnretained(event)
        }

        guard type == .flagsChanged else { return Unmanaged.passUnretained(event) }
        let prefs = Prefs.shared
        let key: TalkKey
        if code == prefs.talkKey.keyCode { key = prefs.talkKey }
        else { return Unmanaged.passUnretained(event) }

        if key.isDown(f) {
            downAt = Date(); downKey = key; chorded = false; startedByThisPress = false
            if isHandsFree() { return Unmanaged.passUnretained(event) }
            let work = DispatchWorkItem { [weak self] in
                guard let self, !self.chorded else { return }
                self.startedByThisPress = true
                self.handler?(.startHold)
            }
            pendingStart = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: work)
        } else {
            guard downKey == key else { return Unmanaged.passUnretained(event) }
            let held = downAt.map { Date().timeIntervalSince($0) } ?? 0
            downAt = nil; downKey = nil
            pendingStart?.cancel()
            if chorded { return Unmanaged.passUnretained(event) }
            if isHandsFree() {
                emit(.finish)
            } else if held < 0.3 {
                if startedByThisPress { emit(.cancel) }  // a tap, not a hold
                if Date().timeIntervalSince(lastTap) < 0.45 {
                    lastTap = .distantPast
                    emit(.startHandsFree)
                } else {
                    lastTap = Date()
                }
            } else if startedByThisPress {
                emit(.finish)
            }
        }
        return Unmanaged.passUnretained(event)
    }
}
