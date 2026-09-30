import AppKit
import AVFoundation
import SwiftUI

@MainActor
final class HistoryModel: ObservableObject {
    @Published var query = "" { didSet { reload() } }
    @Published var items: [Dictation] = []
    @Published var selection: String?
    @Published var playing: String?
    @Published var editing: Dictation?
    private var player: AVAudioPlayer?
    var onPaste: ((String) -> Void)?

    func reload() {
        items = Store.shared.recent(search: query.trimmingCharacters(in: .whitespaces))
        if selection == nil || !items.contains(where: { $0.id == selection }) { selection = items.first?.id }
    }

    /// Save a correction and learn any new names it introduced (runs of capitalized words, e.g. "Jane Doe").
    func saveEdit(_ d: Dictation, _ newText: String) {
        Store.shared.updateText(d.id, newText)
        let before = Set(d.text.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber && $0 != "'" }).map(String.init))
        var learned: [String] = []
        var run: [String] = []
        let words = newText.split(whereSeparator: { $0.isWhitespace || ",.;:!?()\"".contains($0) }).map(String.init)
        func flush() {
            let phrase = run.joined(separator: " ")
            let isNew = run.contains { !before.contains($0.lowercased()) }
            if !run.isEmpty, isNew, phrase.count >= 3, run.count <= 5 { learned.append(phrase) }
            run = []
        }
        for (i, w) in words.enumerated() {
            let cap = w.first?.isUppercase == true || w.dropFirst().contains(where: \.isUppercase)
            // A capital right after a sentence break is just grammar, unless the word is new.
            let sentenceStart = i == 0 || newText.range(of: "[.!?]\\s+\(NSRegularExpression.escapedPattern(for: w))", options: .regularExpression) != nil
            if cap && !(sentenceStart && before.contains(w.lowercased())) { run.append(w) } else { flush() }
        }
        flush()
        if !learned.isEmpty { Config.learn(learned) }
        reload()
    }

    func play(_ d: Dictation) {
        if playing == d.id { player?.stop(); playing = nil; return }
        guard let p = d.audioPath, let pl = try? AVAudioPlayer(contentsOf: URL(fileURLWithPath: p)) else { return }
        player = pl; pl.play(); playing = d.id
        DispatchQueue.main.asyncAfter(deadline: .now() + pl.duration + 0.1) { [weak self] in
            if self?.playing == d.id { self?.playing = nil }
        }
    }
}

struct HistoryView: View {
    @ObservedObject var m: HistoryModel
    @FocusState private var searchFocused: Bool

    var grouped: [(String, [Dictation])] {
        let df = DateFormatter(); df.dateFormat = "EEEE, MMM d"
        let cal = Calendar.current
        var out: [(String, [Dictation])] = []
        for d in m.items {
            let label = cal.isDateInToday(d.createdAt) ? "Today"
                : cal.isDateInYesterday(d.createdAt) ? "Yesterday" : df.string(from: d.createdAt)
            if out.last?.0 == label { out[out.count - 1].1.append(d) } else { out.append((label, [d])) }
        }
        return out
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search dictations", text: $m.query)
                    .textFieldStyle(.plain).font(.system(size: 14)).focused($searchFocused)
                    .onSubmit { pasteSelected() }
                Text("\(m.items.count)").font(.system(size: 11).monospacedDigit()).foregroundStyle(.tertiary)
            }
            .padding(12)
            Divider()
            ScrollViewReader { proxy in
                List(selection: $m.selection) {
                    ForEach(grouped, id: \.0) { day, rows in
                        Section(day) {
                            ForEach(rows) { d in Row(d: d, m: m).tag(d.id).id(d.id) }
                        }
                    }
                }
                .listStyle(.inset)
                .onChange(of: m.selection) { _, id in if let id { proxy.scrollTo(id) } }
            }
            Divider()
            HStack(spacing: 14) {
                Label("↩ paste", systemImage: "").labelStyle(.titleOnly)
                Label("⌘C copy", systemImage: "").labelStyle(.titleOnly)
                Label("Space play", systemImage: "").labelStyle(.titleOnly)
                Spacer()
                Button("Open archive folder") { NSWorkspace.shared.open(Config.daysDir) }
                    .buttonStyle(.link)
            }
            .font(.system(size: 11)).foregroundStyle(.secondary)
            .padding(.horizontal, 12).padding(.vertical, 8)
        }
        .frame(minWidth: 560, minHeight: 440)
        .onAppear { m.reload(); searchFocused = true }
        .onKeyPress(.upArrow) { move(-1); return .handled }
        .onKeyPress(.downArrow) { move(1); return .handled }
        .onKeyPress(.return) { pasteSelected(); return .handled }
        .onKeyPress(.space) {
            if searchFocused && !m.query.isEmpty { return .ignored }
            if let d = selected { m.play(d) }; return .handled
        }
        .onCopyCommand { selected.map { [NSItemProvider(object: $0.text as NSString)] } ?? [] }
        .sheet(item: $m.editing) { d in EditSheet(d: d, m: m) }
    }

    var selected: Dictation? { m.items.first { $0.id == m.selection } }

    func move(_ delta: Int) {
        guard let i = m.items.firstIndex(where: { $0.id == m.selection }) else { m.selection = m.items.first?.id; return }
        m.selection = m.items[max(0, min(m.items.count - 1, i + delta))].id
    }

    func pasteSelected() { if let d = selected { m.onPaste?(d.text) } }
}

struct Row: View {
    let d: Dictation
    @ObservedObject var m: HistoryModel
    @State private var hover = false

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(d.text).font(.system(size: 13)).lineLimit(3).textSelection(.enabled)
                HStack(spacing: 6) {
                    Text(d.createdAt.formatted(date: .omitted, time: .shortened))
                    Text("·"); Text(d.appName.isEmpty ? "Unknown app" : d.appName)
                    Text("·"); Text("\(Int(d.duration.rounded()))s")
                    if !d.pasted { Text("· not pasted").foregroundStyle(.orange) }
                }
                .font(.system(size: 10.5)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            if hover || m.selection == d.id {
                HStack(spacing: 4) {
                    if d.audioPath != nil {
                        Button { m.play(d) } label: { Image(systemName: m.playing == d.id ? "stop.fill" : "play.fill") }
                    }
                    Button { m.editing = d } label: { Image(systemName: "pencil") }.help("Correct it (new names are learned)")
                    Button { Paster.copy(d.text) } label: { Image(systemName: "doc.on.doc") }
                    Button { m.onPaste?(d.text) } label: { Image(systemName: "arrow.turn.down.left") }
                }
                .buttonStyle(.borderless).font(.system(size: 12))
            }
        }
        .padding(.vertical, 3)
        .onHover { hover = $0 }
    }
}

struct EditSheet: View {
    let d: Dictation
    @ObservedObject var m: HistoryModel
    @State private var text = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Correct this dictation").font(.headline)
            Text("Names you fix (like a misspelled client) are added to your vocabulary, so the next dictation gets them right.")
                .font(.caption).foregroundStyle(.secondary)
            TextEditor(text: $text).font(.system(size: 13)).frame(minHeight: 160)
                .scrollContentBackground(.hidden).padding(6)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .textBackgroundColor)))
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save") { m.saveEdit(d, text); dismiss() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(16).frame(width: 520)
        .onAppear { text = d.text }
    }
}

@MainActor
final class HistoryWindow {
    let model = HistoryModel()
    private var window: NSWindow?
    private var previousApp: NSRunningApplication?

    func show() {
        previousApp = NSWorkspace.shared.frontmostApplication
        if window == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 640, height: 560),
                             styleMask: [.titled, .closable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
            w.title = "Dictations"
            w.isReleasedWhenClosed = false
            w.contentView = NSHostingView(rootView: HistoryView(m: model))
            w.center()
            w.setFrameAutosaveName("DictationHistory")
            window = w
            model.onPaste = { [weak self] text in self?.pasteIntoPrevious(text) }
        }
        model.query = ""
        model.reload()
        if let w = window { AppPresence.present(w) }
    }

    private func pasteIntoPrevious(_ text: String) {
        window?.orderOut(nil)
        if let w = window { AppPresence.hidden(w) }
        guard let app = previousApp, app.bundleIdentifier != Bundle.main.bundleIdentifier else { Paster.copy(text); return }
        app.activate()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { Paster.paste(text) }
    }
}
