import AppKit
import ApplicationServices

enum Paster {
    /// Is there a focused element that can take typed text? `nil` means we could not tell
    /// (some apps don't expose accessibility info), in which case we paste anyway.
    static func focusedTextTarget() -> Bool? {
        let sys = AXUIElementCreateSystemWide()
        var v: CFTypeRef?
        guard AXUIElementCopyAttributeValue(sys, kAXFocusedUIElementAttribute as CFString, &v) == .success,
              let el = v else { return nil }
        let e = el as! AXUIElement
        var roleRef: CFTypeRef?
        AXUIElementCopyAttributeValue(e, kAXRoleAttribute as CFString, &roleRef)
        let role = roleRef as? String ?? ""
        if ["AXTextField", "AXTextArea", "AXComboBox", "AXSearchField"].contains(role) { return true }
        var settable: DarwinBoolean = false
        if AXUIElementIsAttributeSettable(e, kAXValueAttribute as CFString, &settable) == .success, settable.boolValue {
            return true
        }
        var editable: CFTypeRef?
        if AXUIElementCopyAttributeValue(e, "AXEditable" as CFString, &editable) == .success,
           (editable as? Bool) == true { return true }
        return false
    }

    /// The character right before the insertion point in the focused field, via Accessibility.
    /// nil when it can't be read (some apps don't expose it) or the cursor is at the very start.
    static func characterBeforeCursor() -> Character? {
        let sys = AXUIElementCreateSystemWide()
        var v: CFTypeRef?
        guard AXUIElementCopyAttributeValue(sys, kAXFocusedUIElementAttribute as CFString, &v) == .success, let el = v else { return nil }
        let e = el as! AXUIElement
        var rangeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(e, kAXSelectedTextRangeAttribute as CFString, &rangeRef) == .success,
              let rangeRef else { return nil }
        var range = CFRange()
        guard AXValueGetValue(rangeRef as! AXValue, .cfRange, &range), range.location > 0 else { return nil }
        // Ask for just the one character; reading the whole value can be huge (a terminal's scrollback).
        var one = CFRange(location: range.location - 1, length: 1)
        if let rv = AXValueCreate(.cfRange, &one) {
            var out: CFTypeRef?
            if AXUIElementCopyParameterizedAttributeValue(e, kAXStringForRangeParameterizedAttribute as CFString, rv, &out) == .success,
               let s = out as? String, let c = s.last { return c }
        }
        var val: CFTypeRef?
        guard AXUIElementCopyAttributeValue(e, kAXValueAttribute as CFString, &val) == .success,
              let str = val as? String else { return nil }
        let ns = str as NSString
        guard range.location - 1 < ns.length else { return nil }
        return Character(ns.substring(with: NSRange(location: range.location - 1, length: 1)))
    }

    /// Continuing after existing text ("…end of sentence.|") needs a space; the start of a field,
    /// a line break, an existing space or an opening bracket/quote does not.
    static func needsLeadingSpace(after prev: Character?, text: String) -> Bool {
        guard let prev, let first = text.first else { return false }
        if prev.isWhitespace || prev.isNewline || first.isWhitespace || first.isNewline { return false }
        if "([{\"'“‘/-@#".contains(prev) { return false }
        if ".,;:!?)]}".contains(first) { return false } // dictation that starts with punctuation attaches directly
        return true
    }

    /// Puts text on the clipboard. Marked transient so clipboard managers skip it.
    static func copy(_ text: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
        pb.setData(Data(), forType: NSPasteboard.PasteboardType("org.nspasteboard.TransientType"))
    }

    /// Paste via the clipboard, then put back whatever was there before.
    static func paste(_ text: String) {
        let pb = NSPasteboard.general
        let saved: [[NSPasteboard.PasteboardType: Data]] = (pb.pasteboardItems ?? []).map { item in
            var d: [NSPasteboard.PasteboardType: Data] = [:]
            for t in item.types { if let data = item.data(forType: t) { d[t] = data } }
            return d
        }
        copy(text)
        let mine = pb.changeCount
        let src = CGEventSource(stateID: .privateState)
        let down = CGEvent(keyboardEventSource: src, virtualKey: 0x09, keyDown: true)
        let up = CGEvent(keyboardEventSource: src, virtualKey: 0x09, keyDown: false)
        down?.flags = .maskCommand; up?.flags = .maskCommand
        down?.post(tap: .cghidEventTap); up?.post(tap: .cghidEventTap)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            guard pb.changeCount == mine, !saved.isEmpty else { return }
            pb.clearContents()
            pb.writeObjects(saved.map { d in
                let item = NSPasteboardItem()
                for (t, data) in d { item.setData(data, forType: t) }
                return item
            })
        }
    }
}
