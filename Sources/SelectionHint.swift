import AppKit
import SwiftUI

/// Highlight some text in a text box and leave it for a moment: a small bubble offers Fix / Rewrite by voice.
/// Reads only the focused element's selection through Accessibility (never the clipboard), and only in
/// editable fields, since a fix has to be pasted back over the selection.
@MainActor
final class SelectionHint {
    var onFix: () -> Void = {}
    var onRewrite: () -> Void = {}
    var suppressed: () -> Bool = { false }

    private var timer: Timer?
    private var lastText = ""
    private var stableSince = Date()
    private var shownFor = ""
    private var dismissedFor = ""
    private let panel: NSPanel
    private let dwell: TimeInterval = 1.6

    init() {
        panel = TabPanel(contentRect: NSRect(x: 0, y: 0, width: 230, height: 40),
                         styleMask: [.nonactivatingPanel, .borderless], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
    }

    func start() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
    }

    func stop() { timer?.invalidate(); timer = nil; hide() }

    private func tick() {
        guard Prefs.shared.selectionHints, !suppressed(),
              NSEvent.pressedMouseButtons == 0,
              let (text, rect) = Self.selection(),
              text.split(whereSeparator: \.isWhitespace).count >= 3 else {
            lastText = ""; if panel.isVisible { hide() }; return
        }
        if text != lastText { lastText = text; stableSince = Date(); if panel.isVisible && shownFor != text { hide() }; return }
        guard !panel.isVisible, text != dismissedFor, Date().timeIntervalSince(stableSince) >= dwell else { return }
        show(for: text, near: rect)
    }

    private func show(for text: String, near rect: NSRect?) {
        shownFor = text
        let view = HintView(
            fix: { [weak self] in self?.dismissedFor = text; self?.hide(); self?.onFix() },
            rewrite: { [weak self] in self?.dismissedFor = text; self?.hide(); self?.onRewrite() },
            close: { [weak self] in self?.dismissedFor = text; self?.hide() })
        panel.contentView = NSHostingView(rootView: view)
        let size = panel.contentView!.fittingSize
        let screen = NSScreen.main?.visibleFrame ?? .zero
        // Above the selection's end if we know where it is, otherwise near the pointer.
        let anchor = rect.map { NSPoint(x: $0.maxX, y: $0.maxY) } ?? NSEvent.mouseLocation
        var origin = NSPoint(x: anchor.x - size.width / 2, y: anchor.y + 8)
        origin.x = min(max(origin.x, screen.minX + 8), screen.maxX - size.width - 8)
        origin.y = min(max(origin.y, screen.minY + 8), screen.maxY - size.height - 8)
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { $0.duration = 0.18; panel.animator().alphaValue = 1 }
        // Don't linger: gone after a few seconds if ignored.
        let t = text
        DispatchQueue.main.asyncAfter(deadline: .now() + 6) { [weak self] in
            if self?.shownFor == t, self?.panel.isVisible == true { self?.dismissedFor = t; self?.hide() }
        }
    }

    func hide() { panel.orderOut(nil); shownFor = "" }

    /// Selected text plus its on-screen rect (AppKit coordinates), from the focused editable element.
    static func selection() -> (String, NSRect?)? {
        let sys = AXUIElementCreateSystemWide()
        var v: CFTypeRef?
        guard AXUIElementCopyAttributeValue(sys, kAXFocusedUIElementAttribute as CFString, &v) == .success, let el = v else { return nil }
        let e = el as! AXUIElement
        guard Paster.focusedTextTarget() == true else { return nil }
        var sel: CFTypeRef?
        guard AXUIElementCopyAttributeValue(e, kAXSelectedTextAttribute as CFString, &sel) == .success,
              let text = sel as? String, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        var rangeRef: CFTypeRef?
        var boundsRef: CFTypeRef?
        var rect: NSRect?
        if AXUIElementCopyAttributeValue(e, kAXSelectedTextRangeAttribute as CFString, &rangeRef) == .success, let rangeRef,
           AXUIElementCopyParameterizedAttributeValue(e, kAXBoundsForRangeParameterizedAttribute as CFString, rangeRef, &boundsRef) == .success,
           let boundsRef {
            var r = CGRect.zero
            if AXValueGetValue(boundsRef as! AXValue, .cgRect, &r), r.width > 0 {
                // AX uses top-left origin; flip to AppKit's bottom-left.
                let h = NSScreen.screens.first?.frame.height ?? 0
                rect = NSRect(x: r.minX, y: h - r.maxY, width: r.width, height: r.height)
            }
        }
        return (text, rect)
    }
}

private struct HintView: View {
    let fix: () -> Void
    let rewrite: () -> Void
    let close: () -> Void
    var body: some View {
        HStack(spacing: 2) {
            HintButton(symbol: "wand.and.stars", title: "Fix", action: fix)
            Divider().frame(height: 16).overlay(Color.white.opacity(0.15))
            HintButton(symbol: "mic.fill", title: "Rewrite by voice", action: rewrite)
            Button(action: close) {
                Image(systemName: "xmark").font(.system(size: 9, weight: .bold)).foregroundStyle(.white.opacity(0.5))
                    .frame(width: 20, height: 20)
            }.buttonStyle(.plain)
        }
        .padding(.horizontal, 6).padding(.vertical, 4)
        .background(Capsule().fill(Color.black.opacity(0.86))
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.14), lineWidth: 1))
            .shadow(color: .black.opacity(0.3), radius: 8, y: 3))
        .padding(8)
    }
}

private struct HintButton: View {
    let symbol: String
    let title: String
    let action: () -> Void
    @State private var hover = false
    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: symbol).font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color(red: 0.55, green: 0.93, blue: 0.95))
                Text(title).font(.system(size: 12, weight: .medium)).foregroundStyle(.white)
            }
            .padding(.horizontal, 9).padding(.vertical, 5)
            .background(Capsule().fill(Color.white.opacity(hover ? 0.12 : 0)))
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}
