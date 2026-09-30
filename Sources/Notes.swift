import AppKit
import SwiftUI

/// A small notepad you can dictate into. Each note is a Markdown file in ~/Dictations/notes.
struct Note: Identifiable, Equatable {
    let url: URL
    var text: String
    var modified: Date
    var id: String { url.path }
    var title: String {
        let first = text.split(separator: "\n").first.map(String.init)?.trimmingCharacters(in: .whitespaces) ?? ""
        return first.isEmpty ? "Untitled note" : String(first.replacingOccurrences(of: "#", with: "").trimmingCharacters(in: .whitespaces).prefix(60))
    }
}

@MainActor
final class NotesModel: ObservableObject {
    static let dir = Config.daysDir.appendingPathComponent("notes")
    @Published var notes: [Note] = []
    @Published var selected: String?
    @Published var status: String?
    private var saveWork: DispatchWorkItem?
    var onDictate: () -> Void = {}

    func load() {
        try? FileManager.default.createDirectory(at: Self.dir, withIntermediateDirectories: true)
        let urls = (try? FileManager.default.contentsOfDirectory(at: Self.dir, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        notes = urls.filter { $0.pathExtension == "md" }.compactMap { u in
            guard let t = try? String(contentsOf: u, encoding: .utf8) else { return nil }
            let m = (try? u.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return Note(url: u, text: t, modified: m)
        }.sorted { $0.modified > $1.modified }
        if selected == nil || !notes.contains(where: { $0.id == selected }) { selected = notes.first?.id }
        if notes.isEmpty { newNote() }
    }

    func newNote() {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd HHmmss"
        let u = Self.dir.appendingPathComponent("\(f.string(from: Date())).md")
        try? "".write(to: u, atomically: true, encoding: .utf8)
        notes.insert(Note(url: u, text: "", modified: Date()), at: 0)
        selected = u.path
    }

    func binding(for id: String) -> Binding<String> {
        Binding(get: { self.notes.first { $0.id == id }?.text ?? "" },
                set: { v in
                    guard let i = self.notes.firstIndex(where: { $0.id == id }) else { return }
                    self.notes[i].text = v
                    self.notes[i].modified = Date()
                    self.scheduleSave(self.notes[i])
                })
    }

    private func scheduleSave(_ n: Note) {
        saveWork?.cancel()
        let w = DispatchWorkItem { try? n.text.write(to: n.url, atomically: true, encoding: .utf8) }
        saveWork = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: w)
    }

    func delete(_ id: String) {
        guard let n = notes.first(where: { $0.id == id }) else { return }
        // Trash, not rm: a note deleted by accident can be dragged back.
        try? FileManager.default.trashItem(at: n.url, resultingItemURL: nil)
        notes.removeAll { $0.id == id }
        selected = notes.first?.id
        if notes.isEmpty { newNote() }
    }

}

struct NotesView: View {
    @ObservedObject var m: NotesModel
    @FocusState private var editorFocused: Bool

    var body: some View {
        NavigationSplitView {
            List(selection: $m.selected) {
                ForEach(m.notes) { n in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(n.title).font(.system(size: 13, weight: .medium)).lineLimit(1)
                        Text(n.modified.formatted(date: .abbreviated, time: .shortened))
                            .font(.system(size: 10.5)).foregroundStyle(.secondary)
                    }
                    .tag(n.id)
                    .contextMenu { Button("Move to Trash", role: .destructive) { m.delete(n.id) } }
                }
            }
            .navigationSplitViewColumnWidth(min: 170, ideal: 190)
        } detail: {
            if let id = m.selected {
                TextEditor(text: m.binding(for: id))
                    .font(.system(size: 14))
                    .scrollContentBackground(.hidden)
                    .padding(12)
                    .focused($editorFocused)
                    .onAppear { editorFocused = true }
                    .overlay(alignment: .topLeading) {
                        if m.binding(for: id).wrappedValue.isEmpty {
                            Text("Type, or hold \(Prefs.shared.talkKey.shortName) to dictate into this note.\nThe first line becomes the title.")
                                .font(.system(size: 14)).foregroundStyle(.tertiary)
                                .padding(.horizontal, 17).padding(.vertical, 12).allowsHitTesting(false)
                        }
                    }
            }
        }
        .toolbar {
            ToolbarItemGroup {
                if let s = m.status { Text(s).font(.caption).foregroundStyle(.secondary) }
                Button { m.newNote(); editorFocused = true } label: { Label("New note", systemImage: "square.and.pencil") }
                    .help("New note  ⌘N").keyboardShortcut("n")
                Button { editorFocused = true; m.onDictate() } label: { Label("Dictate", systemImage: "mic.fill") }
                    .help("Dictate into this note (or just hold your talk key)")
                Button { NSWorkspace.shared.open(NotesModel.dir) } label: { Label("Show in Finder", systemImage: "folder") }
                    .help("Notes are Markdown files in ~/Dictations/notes")
            }
        }
        .frame(minWidth: 560, minHeight: 360)
        .onAppear { m.load() }
    }
}

@MainActor
final class NotesWindow {
    let model = NotesModel()
    private var window: NSWindow?

    func show() {
        if window == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 640, height: 440),
                             styleMask: [.titled, .closable, .resizable, .miniaturizable, .fullSizeContentView],
                             backing: .buffered, defer: false)
            w.title = "Notes"
            w.isReleasedWhenClosed = false
            w.level = .floating // stays above what you're working on, like a sticky note
            w.contentView = NSHostingView(rootView: NotesView(m: model))
            w.center()
            w.setFrameAutosaveName("DictationNotes")
            window = w
        }
        model.load()
        if let w = window { AppPresence.present(w) }
    }
}
