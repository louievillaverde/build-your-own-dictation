import AppKit
import Combine
import SwiftUI

/// A small glass handle on a screen edge. Hover to reveal talk / history / paste last / settings;
/// drag it to any edge and it snaps there. Sits inside the visible frame, so it never covers the Dock.
@MainActor
final class TabModel: ObservableObject {
    @Published var expanded = false
    @Published var edge: TabEdge = .right
    @Published var keySymbol = "⌥"
    @Published var talkKeyName = "right ⌥"
    /// A dictation is waiting on the clipboard because nothing was focused when it finished.
    @Published var unpasted = false
    @Published var hop = false
    /// Smoke tests only: forces a descriptor bubble without a real pointer.
    @Published var previewHover: Int?
    var vertical: Bool { edge.vertical }
    var onTalk: () -> Void = {}
    var onFix: () -> Void = {}
    var onNotes: () -> Void = {}
    var onMore: () -> Void = {}
    var onHistory: () -> Void = {}
    var onPasteLast: () -> Void = {}
    var onSettings: () -> Void = {}
    var onDrag: (_ ended: Bool) -> Void = { _ in }

    func bounce() {
        withAnimation(.spring(response: 0.22, dampingFraction: 0.45)) { hop = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.5)) { self.hop = false }
        }
    }
}

private let tabMargin: CGFloat = 10
private let collapsedLength: CGFloat = 40
private let collapsedThickness: CGFloat = 8
private let buttonSize: CGFloat = 30
private let buttonGap: CGFloat = 8
private let buttonCount: CGFloat = 4
private let gripLength: CGFloat = 14
private let stackLength = buttonSize * buttonCount + buttonGap * buttonCount + gripLength
/// Room beside the icons for the descriptor bubble. Sized for the longest label so it never clips.
private func tipRoom(_ vertical: Bool) -> CGFloat { vertical ? 290 : 48 }

private let aqua = Color(red: 0.55, green: 0.93, blue: 0.95)

struct EdgeTabView: View {
    @ObservedObject var m: TabModel
    @State private var hovered: Int?

    var body: some View {
        ZStack(alignment: alignment) {
            Color.clear
            Group {
                if m.expanded { icons } else { handle }
            }
            .padding(tabMargin)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contextMenu {
            Button("Fix selected text  ⌃⌥F") { m.onFix() }
            Button("Paste last dictation  ⌃⌥V") { m.onPasteLast() }
            Button("History  ⌃⌥H") { m.onHistory() }
            Divider()
            Button("Settings…") { m.onSettings() }
        }
        .gesture(DragGesture(minimumDistance: 4, coordinateSpace: .global)
            .onChanged { _ in m.onDrag(false) }
            .onEnded { _ in m.onDrag(true) })
    }

    private var alignment: Alignment {
        switch m.edge { case .right: return .trailing; case .left: return .leading; case .bottom: return .bottom; case .top: return .top }
    }
    /// Offset that nudges toward the screen's center, for the hop.
    private var inward: CGSize {
        let d: CGFloat = m.hop ? 5 : 0
        switch m.edge { case .right: return CGSize(width: -d, height: 0); case .left: return CGSize(width: d, height: 0)
        case .bottom: return CGSize(width: 0, height: -d); case .top: return CGSize(width: 0, height: d) }
    }

    var handle: some View {
        Capsule()
            .fill(Color.black.opacity(0.72))
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.22), lineWidth: 1))
            .overlay(alignment: m.vertical ? .top : .trailing) {
                if m.unpasted { Circle().fill(Color.orange).frame(width: 7, height: 7).offset(x: m.vertical ? 0 : 3, y: m.vertical ? -3 : 0) }
            }
            .frame(width: m.vertical ? collapsedThickness : collapsedLength,
                   height: m.vertical ? collapsedLength : collapsedThickness)
            .offset(inward)
    }

    struct Item { let symbol: String; let title: String; let key: String?; let accent: Bool }
    // Only what you'd click lives here. Keyboard-first actions (fix, task, paste last) sit behind ⋯ and on their keys.
    private var items: [Item] {[
        Item(symbol: "mic.fill", title: "Dictate", key: "hold \(m.talkKeyName)", accent: true),
        Item(symbol: "note.text", title: "Notes", key: nil, accent: false),
        m.unpasted ? Item(symbol: "clock.arrow.circlepath", title: "Paste waiting dictation", key: "⌃⌥V", accent: false)
                   : Item(symbol: "clock.arrow.circlepath", title: "History", key: "⌃⌥H", accent: false),
        Item(symbol: "ellipsis", title: "More: fix, task, settings", key: nil, accent: false),
    ]}
    private func action(_ i: Int) {
        [m.onTalk, m.onNotes, m.unpasted ? m.onPasteLast : m.onHistory, m.onMore][i]()
    }

    var icons: some View {
        let layout = m.vertical ? AnyLayout(VStackLayout(spacing: buttonGap)) : AnyLayout(HStackLayout(spacing: buttonGap))
        return layout {
            ForEach(Array(items.enumerated()), id: \.offset) { i, item in
                IconButton(item: item, badge: i == 2 && m.unpasted, hovered: (hovered ?? m.previewHover) == i) { action(i) }
                    .onHover { hovered = $0 ? i : (hovered == i ? nil : hovered) }
                    .overlay(alignment: tipAlignment) {
                        if (hovered ?? m.previewHover) == i { Tip(title: item.title, key: item.key).fixedSize().offset(tipOffset).allowsHitTesting(false)
                            .transition(.opacity.combined(with: .scale(scale: 0.92))) }
                    }
                    .transition(.scale(scale: 0.4).combined(with: .opacity)
                        .animation(.spring(response: 0.3, dampingFraction: 0.7).delay(Double(i) * 0.03)))
            }
            Grip(vertical: m.vertical)
        }
        .animation(.easeOut(duration: 0.12), value: hovered)
    }

    private var tipAlignment: Alignment {
        switch m.edge { case .right: return .trailing; case .left: return .leading; case .bottom: return .bottom; case .top: return .top }
    }
    private var tipOffset: CGSize {
        let d = buttonSize + 8
        switch m.edge { case .right: return CGSize(width: -d, height: 0); case .left: return CGSize(width: d, height: 0)
        case .bottom: return CGSize(width: 0, height: -d); case .top: return CGSize(width: 0, height: d) }
    }
}

struct IconButton: View {
    let item: EdgeTabView.Item
    let badge: Bool
    let hovered: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: item.symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(item.accent ? aqua : .white.opacity(hovered ? 1 : 0.82))
                .frame(width: buttonSize, height: buttonSize)
                .background(
                    Circle().fill(Color.black.opacity(hovered ? 0.88 : 0.78))
                        .overlay(Circle().strokeBorder(Color.white.opacity(hovered ? 0.35 : 0.18), lineWidth: 1))
                        .shadow(color: .black.opacity(0.35), radius: 4, y: 2)
                )
                .overlay(alignment: .topTrailing) {
                    if badge { Circle().fill(Color.orange).frame(width: 8, height: 8).offset(x: 1, y: -1) }
                }
                .scaleEffect(hovered ? 1.08 : 1)
        }
        .buttonStyle(.plain)
    }
}

/// Fathom-style drag handle: only there while the tab is open, and shows the grab cursor.
struct Grip: View {
    let vertical: Bool
    @State private var hover = false
    var body: some View {
        Image(systemName: vertical ? "circle.grid.2x3.fill" : "circle.grid.3x2.fill")
            .font(.system(size: 8, weight: .bold))
            .foregroundStyle(.white.opacity(hover ? 0.8 : 0.45))
            .frame(width: vertical ? buttonSize : gripLength, height: vertical ? gripLength : buttonSize)
            .background(Capsule().fill(Color.black.opacity(hover ? 0.7 : 0.45)))
            .onHover { h in
                hover = h
                if h { NSCursor.openHand.push() } else { NSCursor.pop() }
            }
            .help("Drag to move")
    }
}

/// The descriptor bubble, in Wispr's shape: a label plus the key that does the same thing.
struct Tip: View {
    let title: String
    let key: String?
    var body: some View {
        HStack(spacing: 6) {
            Text(title).font(.system(size: 12.5, weight: .medium)).foregroundStyle(.white)
            if let key { Text(key).font(.system(size: 12, weight: .bold)).foregroundStyle(.white.opacity(0.9)) }
        }
        .padding(.horizontal, 12).padding(.vertical, 7)
        .background(Capsule().fill(Color.black.opacity(0.86))
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.14), lineWidth: 1)))
    }
}

final class TabPanel: NSPanel {
    override var canBecomeKey: Bool { false }  // clicking the tab must never steal focus from where you type
    override var canBecomeMain: Bool { false }
}

@MainActor
final class EdgeTab {
    let model = TabModel()
    private let panel: TabPanel
    private var watcher: Timer?
    private var dragging = false
    private var grab: CGPoint = .zero
    private var hiddenForRecording = false
    private var snapping = false
    private var bag: Set<AnyCancellable> = []

    init() {
        panel = TabPanel(contentRect: .zero, styleMask: [.nonactivatingPanel, .borderless],
                         backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.acceptsMouseMovedEvents = true
        let host = NSHostingView(rootView: EdgeTabView(m: model))
        panel.contentView = host
        let hover = HoverView(frame: .zero) { [weak self] inside in
            if inside { self?.setExpanded(true) }
        }
        hover.autoresizingMask = [.width, .height]
        host.addSubview(hover)
        model.onDrag = { [weak self] ended in self?.drag(ended: ended) }

        let p = Prefs.shared
        p.$showTab.combineLatest(p.$tabEdge).receive(on: RunLoop.main)
            .sink { [weak self] _, _ in DispatchQueue.main.async { self?.refresh() } }
            .store(in: &bag)
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                               object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
    }

    func setRecording(_ on: Bool) {
        hiddenForRecording = on
        refresh()
    }

    func refresh() {
        let p = Prefs.shared
        guard p.showTab, !hiddenForRecording else { panel.orderOut(nil); return }
        if snapping || dragging { return }
        model.edge = p.tabEdge
        model.keySymbol = p.talkKey.short
        model.talkKeyName = p.talkKey.shortName
        panel.setFrame(frame(expanded: model.expanded), display: true)
        panel.orderFrontRegardless()
    }

    private var screen: NSScreen? { NSScreen.main ?? NSScreen.screens.first }

    /// Panel frame for the saved edge + position, pinned inside the visible frame (clear of Dock and menu bar).
    private func frame(expanded: Bool) -> NSRect {
        let p = Prefs.shared
        let vf = screen?.visibleFrame ?? .zero
        // Horizontal tabs get side room so an end icon's bubble can overhang without clipping.
        let len = (expanded ? stackLength + (p.tabEdge.vertical ? 0 : 240) : collapsedLength) + tabMargin * 2
        let thick = (expanded ? buttonSize + tipRoom(p.tabEdge.vertical) : collapsedThickness) + tabMargin * 2
        let inset: CGFloat = 2
        let t = CGFloat(min(max(p.tabPosition, 0), 1))
        switch p.tabEdge {
        case .bottom, .top:
            let x = min(max(vf.minX + t * vf.width - len / 2, vf.minX), vf.maxX - len)
            let y = p.tabEdge == .bottom ? vf.minY + inset : vf.maxY - thick - inset
            return NSRect(x: x, y: y, width: len, height: thick)
        case .left, .right:
            let y = min(max(vf.minY + t * vf.height - len / 2, vf.minY), vf.maxY - len)
            let x = p.tabEdge == .left ? vf.minX + inset : vf.maxX - thick - inset
            return NSRect(x: x, y: y, width: thick, height: len)
        }
    }

    private func setExpanded(_ on: Bool, watch: Bool = true) {
        guard model.expanded != on, !dragging else { return }
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { model.expanded = on }
        panel.setFrame(frame(expanded: on), display: true, animate: false)
        watcher?.invalidate()
        if on && watch {
            // Collapse once the pointer has been away for a moment.
            var away = 0
            watcher = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self, !self.dragging else { return }
                    let inside = self.hotRect().insetBy(dx: -8, dy: -8).contains(NSEvent.mouseLocation)
                    away = inside ? 0 : away + 1
                    if away >= 3 { self.setExpanded(false) }
                }
            }
        }
    }

    /// The part of the expanded panel the icons occupy (the rest is room for the descriptor bubble).
    private func hotRect() -> NSRect {
        let f = panel.frame
        let t = buttonSize + tabMargin * 2
        switch Prefs.shared.tabEdge {
        case .right: return NSRect(x: f.maxX - t, y: f.minY, width: t, height: f.height)
        case .left: return NSRect(x: f.minX, y: f.minY, width: t, height: f.height)
        case .bottom: return NSRect(x: f.minX, y: f.minY, width: f.width, height: t)
        case .top: return NSRect(x: f.minX, y: f.maxY - t, width: f.width, height: t)
        }
    }

    func preview(hover: Int?) {
        model.previewHover = hover
        setExpanded(hover != nil, watch: false)
    }

    /// The ⋯ menu: keyboard-first actions, each showing its key.
    func showMoreMenu(fix: @escaping () -> Void, pasteLast: @escaping () -> Void,
                      settings: @escaping () -> Void) {
        let menu = NSMenu()
        func add(_ title: String, _ key: String, _ mods: NSEvent.ModifierFlags, _ symbol: String, _ f: @escaping () -> Void) {
            let i = ClosureMenuItem(title: title, action: f)
            i.keyEquivalent = key; i.keyEquivalentModifierMask = mods
            i.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
            menu.addItem(i)
        }
        add("Fix selected text", "f", [.control, .option], "wand.and.stars", fix)
        add("Paste last dictation", "v", [.control, .option], "doc.on.clipboard", pasteLast)
        menu.addItem(.separator())
        add("Settings…", "", [], "gearshape", settings)
        let loc = panel.convertPoint(fromScreen: NSEvent.mouseLocation)
        menu.popUp(positioning: nil, at: loc, in: panel.contentView)
    }

    func notifyUnpasted(_ on: Bool) {
        model.unpasted = on
        if on { model.bounce() }
    }

    private func nearestEdge(_ pt: NSPoint, _ vf: NSRect) -> TabEdge {
        let d: [(TabEdge, CGFloat)] = [(.left, pt.x - vf.minX), (.right, vf.maxX - pt.x),
                                       (.bottom, pt.y - vf.minY), (.top, vf.maxY - pt.y)]
        return d.min { $0.1 < $1.1 }!.0
    }

    /// Dragging shrinks the tab to a small puck under the cursor that turns to match the nearest edge,
    /// then springs into place on release. It stays collapsed until the next hover.
    private func drag(ended: Bool) {
        let mouse = NSEvent.mouseLocation
        let vf = screen?.visibleFrame ?? .zero
        let edge = nearestEdge(mouse, vf)
        let puck = edge.vertical ? NSSize(width: collapsedThickness + tabMargin * 2, height: collapsedLength + tabMargin * 2)
                                 : NSSize(width: collapsedLength + tabMargin * 2, height: collapsedThickness + tabMargin * 2)
        if !dragging {
            dragging = true
            watcher?.invalidate()
            NSCursor.closedHand.push()
            withAnimation(.spring(response: 0.22, dampingFraction: 0.85)) { model.expanded = false }
        }
        if !ended {
            if model.edge != edge { withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) { model.edge = edge } }
            panel.setFrame(NSRect(x: mouse.x - puck.width / 2, y: mouse.y - puck.height / 2,
                                  width: puck.width, height: puck.height), display: true)
            return
        }
        NSCursor.pop()
        let p = Prefs.shared
        snapping = true  // the edge pref's own refresh would jump the frame mid-animation
        p.tabPosition = edge.vertical ? Double((mouse.y - vf.minY) / vf.height) : Double((mouse.x - vf.minX) / vf.width)
        p.tabEdge = edge
        model.edge = edge
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.34
            ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.3, 1.3, 0.5, 1) // slight overshoot, then settle
            panel.animator().setFrame(frame(expanded: false), display: true)
        }, completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                self?.snapping = false
                self?.dragging = false
            }
        })
    }
}

/// Tracks the pointer entering the panel without swallowing clicks meant for SwiftUI.
final class HoverView: NSView {
    private let onChange: (Bool) -> Void
    init(frame: NSRect, onChange: @escaping (Bool) -> Void) {
        self.onChange = onChange
        super.init(frame: frame)
    }
    required init?(coder: NSCoder) { fatalError() }
    override func updateTrackingAreas() {
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                       owner: self, userInfo: nil))
    }
    override func mouseEntered(with event: NSEvent) { onChange(true) }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

/// NSMenuItem that runs a closure, so menus can be built inline.
final class ClosureMenuItem: NSMenuItem {
    private let run: () -> Void
    init(title: String, action run: @escaping () -> Void) {
        self.run = run
        super.init(title: title, action: #selector(fire), keyEquivalent: "")
        target = self
    }
    required init(coder: NSCoder) { fatalError() }
    @objc private func fire() { run() }
}
