import AppKit
import SwiftUI

@MainActor
final class OverlayModel: ObservableObject {
    enum Phase: Equatable { case hidden, listening, working, done(String), notice(String, String), error(String) }
    @Published var phase: Phase = .hidden
    @Published var live = ""
    @Published var handsFree = false
    @Published var elapsed: Double = 0
    @Published var keySymbol = "⌥"
    /// What this recording is for, when it isn't plain dictation.
    @Published var caption: String?
    @Published var workingLabel = "Transcribing"
    @Published var style: PillStyle = Prefs.shared.pillStyle
    @Published var graphics = Prefs.shared.showGraphics
    @Published var compact = Prefs.shared.compactPill
    /// Read every frame by the shader, so it is deliberately not @Published.
    nonisolated(unsafe) var level: Float = 0

    nonisolated func push(level l: Float) { level = l }

    var shaderPhase: Float {
        switch phase {
        case .hidden, .listening: return 0
        case .working: return 1
        case .done: return 2
        case .notice: return 3
        case .error: return 4
        }
    }
}

/// Compact is the default: tall enough to read, small enough to stay out of the way.
private var pillHeight: CGFloat { Prefs.shared.compactPill ? 34 : 46 }
private var baseFont: CGFloat { Prefs.shared.compactPill ? 12 : 13.5 }
private var textWidth: CGFloat { Prefs.shared.compactPill ? 300 : 380 }
private let glowMargin: CGFloat = 18

struct PillView: View {
    @ObservedObject var m: OverlayModel

    var body: some View {
        VStack {
            Spacer(minLength: 0)
            if m.phase != .hidden {
                content
                    .frame(height: pillHeight)
                    .padding(.leading, !m.graphics ? pillHeight * 0.95 : (m.style == .neon || m.style == .studio) ? pillHeight * 1.95 : pillHeight - 2)
                    .padding(.trailing, m.compact ? 15 : 20)
                    .frame(minWidth: m.compact ? 104 : 128)
                    // Shader first, blur second: a later .background() draws BEHIND an earlier one.
                    .background(
                        GlassSurface(margin: glowMargin, level: { [m] in m.level },
                                     phase: { [m] in MainActor.assumeIsolated { m.shaderPhase } })
                            .padding(-glowMargin)
                    )
                    .background(
                        EmptyView()
                    )
                    .transition(.asymmetric(insertion: .scale(scale: 0.86).combined(with: .opacity),
                                            removal: .scale(scale: 0.96).combined(with: .opacity)))
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, glowMargin + 4)
        .animation(.spring(response: 0.34, dampingFraction: 0.8), value: m.phase)
        .animation(.spring(response: 0.4, dampingFraction: 0.86), value: m.live.isEmpty)
    }

    @ViewBuilder var content: some View {
        switch m.phase {
        case .listening:
            HStack(spacing: 14) {
                if let c = m.caption {
                    Text(c).font(.system(size: 11, weight: .semibold))
                        .lineLimit(1).fixedSize()
                        .foregroundStyle(Color(red: 0.55, green: 0.93, blue: 0.95))
                }
                if m.live.isEmpty {
                    // Same breathing room as the live words: clear of the meter, and wide enough
                    // that the timer isn't crammed against it (2026-09-25).
                    Text("Listening")
                        .font(m.graphics && m.style == .neon ? .system(size: baseFont - 1, weight: .medium, design: .monospaced)
                              : .system(size: baseFont - 0.5, weight: .medium))
                        .foregroundStyle(.white.opacity(0.55))
                        .padding(.leading, 7.5)
                        .padding(.trailing, -3) // equal gap either side: ~11pt from the meter, ~11pt to the timer
                } else {
                    Text(tail(m.live))
                        .font(m.graphics && m.style == .neon ? .system(size: baseFont - 1, weight: .medium, design: .monospaced)
                              : m.graphics && m.style == .studio ? .system(size: baseFont + 0.5, weight: .regular, design: .serif) : .system(size: baseFont, weight: .medium))
                        .foregroundStyle(m.graphics && m.style == .studio ? Color(red: 0.98, green: 0.9, blue: 0.74) : .white.opacity(0.94))
                        .shadow(color: m.graphics && m.style == .neon ? Color(red: 0, green: 0.9, blue: 1).opacity(0.55) : .clear, radius: 4)
                        .lineLimit(1).truncationMode(.head)
                        .frame(maxWidth: textWidth, alignment: .trailing)
                        .mask(LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.14)],
                                             startPoint: .leading, endPoint: .trailing))
                }
                Text(timeString(m.elapsed))
                    .font(.system(size: baseFont - 2, weight: .medium).monospacedDigit())
                    .lineLimit(1).fixedSize()
                    .foregroundStyle(.white.opacity(0.38))
                if m.handsFree {
                    Text("tap \(m.keySymbol) to finish")
                        .font(.system(size: 10.5, weight: .semibold))
                        .lineLimit(1).fixedSize()
                        .padding(.horizontal, 7).padding(.vertical, 3)
                        .background(Capsule().fill(Color(red: 0.30, green: 0.84, blue: 0.88).opacity(0.16)))
                        .foregroundStyle(Color(red: 0.55, green: 0.93, blue: 0.95))
                }
            }
        case .working:
            Text(m.workingLabel)
                .padding(.leading, statusInset)
                .font(.system(size: 13, weight: .medium)).foregroundStyle(.white.opacity(0.78))
                .lineLimit(1).fixedSize()
        case .done(let preview):
            HStack(spacing: 10) {
                // Sized to the words, not stretched to the max: a short take made a long empty pill.
                Text(clip(preview)).font(.system(size: baseFont - 0.5, weight: .medium)).foregroundStyle(.white.opacity(0.9))
                    .lineLimit(1).fixedSize()
                    .padding(.leading, statusInset)
                Text("Pasted").font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(Color(red: 0.55, green: 0.93, blue: 0.95))
            }
        case .notice(let title, let hint):
            HStack(spacing: 8) {
                Text(title).font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
                    .lineLimit(1).fixedSize()
                    .padding(.leading, statusInset)
                Text(hint).font(.system(size: 12.5)).foregroundStyle(.white.opacity(0.55))
                    .lineLimit(1).fixedSize()
            }
        case .error(let msg):
            Text(msg).font(.system(size: 13, weight: .medium)).foregroundStyle(.white.opacity(0.92))
                .lineLimit(1).fixedSize()
                .padding(.leading, statusInset)
        case .hidden:
            EmptyView()
        }
    }

    /// Same gap from the meter as "Listening" has, so every state lines up (2026-09-25).
    private let statusInset: CGFloat = 7.5
    /// A pasted preview longer than the pill can hold ends in "…" instead of stretching it.
    private func clip(_ s: String) -> String {
        let max = Prefs.shared.compactPill ? 40 : 52
        return s.count > max ? String(s.prefix(max - 1)).trimmingCharacters(in: .whitespaces) + "…" : s
    }
    private func tail(_ s: String) -> String { s.count > 90 ? String(s.suffix(90)) : s }
    private func timeString(_ t: Double) -> String { String(format: "%d:%02d", Int(t) / 60, Int(t) % 60) }
}

@MainActor
final class Overlay {
    let model = OverlayModel()
    private let panel: NSPanel
    private var hideWork: DispatchWorkItem?

    init() {
        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 760, height: pillHeight + glowMargin * 2 + 30),
                        styleMask: [.nonactivatingPanel, .borderless], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .statusBar
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        let host = NSHostingView(rootView: PillView(m: model))
        host.frame = panel.contentView!.bounds
        host.autoresizingMask = [.width, .height]
        panel.contentView = host
    }

    private func place() {
        let screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? NSScreen.main
        guard let vf = screen?.visibleFrame else { return }
        panel.setFrameOrigin(NSPoint(x: vf.midX - panel.frame.width / 2, y: vf.minY))
    }

    func show(_ phase: OverlayModel.Phase, hideAfter: Double? = nil) {
        hideWork?.cancel()
        if model.phase == .hidden {
            model.style = Prefs.shared.pillStyle; model.graphics = Prefs.shared.showGraphics; model.compact = Prefs.shared.compactPill
            place(); panel.orderFrontRegardless()
        }
        if phase == .working && model.phase != .working { model.workingLabel = "Transcribing" }
        model.phase = phase
        if let s = hideAfter {
            let w = DispatchWorkItem { [weak self] in self?.hide() }
            hideWork = w
            DispatchQueue.main.asyncAfter(deadline: .now() + s, execute: w)
        }
    }

    func hide() {
        model.phase = .hidden
        model.live = ""
        model.level = 0
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            if self?.model.phase == .hidden { self?.panel.orderOut(nil) }
        }
    }
}
