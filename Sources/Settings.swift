import AppKit
import SwiftUI
import ServiceManagement

/// Modifier keys that can be held on their own as the talk key.
enum TalkKey: String, CaseIterable, Identifiable {
    case fn, leftControl, rightControl, leftOption, rightOption, rightCommand, rightShift
    var id: String { rawValue }
    var label: String {
        switch self {
        case .fn: return "Fn / 🌐"
        case .leftControl: return "Left Control ⌃"
        case .rightControl: return "Right Control ⌃"
        case .leftOption: return "Left Option ⌥"
        case .rightOption: return "Right Option ⌥"
        case .rightCommand: return "Right Command ⌘"
        case .rightShift: return "Right Shift ⇧"
        }
    }
    /// For hints: "right ⌥", "fn".
    var shortName: String {
        switch self {
        case .fn: return "fn"
        case .leftControl: return "left ⌃"
        case .rightControl: return "right ⌃"
        case .leftOption: return "left ⌥"
        case .rightOption: return "right ⌥"
        case .rightCommand: return "right ⌘"
        case .rightShift: return "right ⇧"
        }
    }
    var short: String {
        switch self {
        case .fn: return "fn"
        case .leftControl, .rightControl: return "⌃"
        case .leftOption, .rightOption: return "⌥"
        case .rightCommand: return "⌘"
        case .rightShift: return "⇧"
        }
    }
    var keyCode: Int64 {
        switch self {
        case .fn: return 63
        case .leftControl: return 59
        case .rightControl: return 62
        case .leftOption: return 58
        case .rightOption: return 61
        case .rightCommand: return 54
        case .rightShift: return 60
        }
    }
    /// Device-dependent flag bit, so left and right are told apart.
    func isDown(_ flags: CGEventFlags) -> Bool {
        let raw = flags.rawValue
        switch self {
        case .fn: return flags.contains(.maskSecondaryFn)
        case .leftControl: return raw & 0x0001 != 0
        case .rightControl: return raw & 0x2000 != 0
        case .leftOption: return raw & 0x0020 != 0
        case .rightOption: return raw & 0x0040 != 0
        case .rightCommand: return raw & 0x0010 != 0
        case .rightShift: return raw & 0x0004 != 0
        }
    }
}

enum PillStyle: String, CaseIterable, Identifiable {
    case water, studio, neon
    var id: String { rawValue }
    var label: String { ["water": "Deep Water", "studio": "On Air", "neon": "Neo Noir"][rawValue]! }
    var index: Int { PillStyle.allCases.firstIndex(of: self)! }
}

enum TabEdge: String, CaseIterable, Identifiable {
    case bottom, left, right, top
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
    var vertical: Bool { self == .left || self == .right }
}

/// What transcribes the take when the chosen engine fails (no key, no credit, timeout).
enum Fallback: String, CaseIterable, Identifiable {
    case apple, deepgram, scribe, none
    var id: String { rawValue }
    var label: String {
        switch self {
        case .apple: return "Apple on-device"
        case .deepgram: return Engine.deepgram.label
        case .scribe: return Engine.scribe.label
        case .none: return "None"
        }
    }
    var engine: Engine? { self == .deepgram ? .deepgram : (self == .scribe ? .scribe : nil) }
}

final class Prefs: ObservableObject {
    static let shared = Prefs()

    /// A Dock icon makes Dictation findable like any app (the menu-bar icon can hide behind the notch).
    static func applyDockPolicy() {
        DispatchQueue.main.async {
            NSApp.setActivationPolicy(UserDefaults.standard.bool(forKey: "showInDock") ? .regular : .accessory)
        }
    }
    private let d = UserDefaults.standard

    @Published var talkKey: TalkKey { didSet { d.set(talkKey.rawValue, forKey: "talkKey") } }
    @Published var pauseMedia: Bool { didSet { d.set(pauseMedia, forKey: "pauseMedia") } }
    @Published var sounds: Bool { didSet { d.set(sounds, forKey: "sounds") } }
    @Published var polish: Bool { didSet { d.set(polish, forKey: "polish") } }
    // Where the Haiku polish runs. Terminal-style apps default off: you talk to Claude there, and Claude
    // doesn't need tidy prose. Client-facing places (email, chat, the rest) default on.
    @Published var polishInTerminal: Bool { didSet { d.set(polishInTerminal, forKey: "polishTerminal2") } }
    @Published var polishInChat: Bool { didSet { d.set(polishInChat, forKey: "polishChat") } }
    @Published var polishInEmail: Bool { didSet { d.set(polishInEmail, forKey: "polishEmail") } }
    @Published var polishElsewhere: Bool { didSet { d.set(polishElsewhere, forKey: "polishElsewhere") } }
    @Published var livePreview: Bool { didSet { d.set(livePreview, forKey: "livePreview") } }
    @Published var engine: Engine {
        didSet {
            d.set(engine.rawValue, forKey: "engine")
            // A fallback can't be the engine it backs up.
            if fallback.engine == engine { fallback = .apple }
        }
    }
    @Published var fallback: Fallback { didSet { d.set(fallback.rawValue, forKey: "fallback") } }
    @Published var selectionHints: Bool { didSet { d.set(selectionHints, forKey: "selectionHints") } }
    @Published var waterMotion: Double { didSet { d.set(waterMotion, forKey: "waterMotion") } }
    @Published var compactPill: Bool { didSet { d.set(compactPill, forKey: "compactPill") } }
    @Published var showGraphics: Bool { didSet { d.set(showGraphics, forKey: "showGraphics") } }
    @Published var pillStyle: PillStyle { didSet { d.set(pillStyle.rawValue, forKey: "pillStyle") } }
    @Published var showInDock: Bool { didSet { d.set(showInDock, forKey: "showInDock"); Prefs.applyDockPolicy() } }
    @Published var showTab: Bool { didSet { d.set(showTab, forKey: "showTab") } }
    @Published var tabEdge: TabEdge { didSet { d.set(tabEdge.rawValue, forKey: "tabEdge") } }
    /// Position along the edge, 0...1.
    @Published var tabPosition: Double { didSet { d.set(tabPosition, forKey: "tabPosition") } }

    private init() {
        d.register(defaults: ["talkKey": TalkKey.rightOption.rawValue, "pauseMedia": true, "sounds": true,
                              "polish": true, "polishTerminal2": false, "polishChat": true, "polishEmail": true, "polishElsewhere": true, "livePreview": true, "engine": Engine.deepgram.rawValue, "fallback": Fallback.apple.rawValue,
                              "showTab": true, "showInDock": true, "pillStyle": PillStyle.water.rawValue, "compactPill": true, "showGraphics": true, "waterMotion": 0.35, "selectionHints": true, "tabEdge": TabEdge.right.rawValue, "tabPosition": 0.5])
        talkKey = TalkKey(rawValue: d.string(forKey: "talkKey") ?? "") ?? .rightOption
        pauseMedia = d.bool(forKey: "pauseMedia")
        sounds = d.bool(forKey: "sounds")
        polish = d.bool(forKey: "polish")
        polishInTerminal = d.bool(forKey: "polishTerminal2")
        polishInChat = d.bool(forKey: "polishChat")
        polishInEmail = d.bool(forKey: "polishEmail")
        polishElsewhere = d.bool(forKey: "polishElsewhere")
        livePreview = d.bool(forKey: "livePreview")
        fallback = Fallback(rawValue: d.string(forKey: "fallback") ?? "") ?? .apple
        engine = Engine(rawValue: d.string(forKey: "engine") ?? "") ?? .deepgram
        showTab = d.bool(forKey: "showTab")
        showInDock = d.bool(forKey: "showInDock")
        pillStyle = PillStyle(rawValue: d.string(forKey: "pillStyle") ?? "") ?? .water
        waterMotion = d.double(forKey: "waterMotion")
        compactPill = d.bool(forKey: "compactPill")
        showGraphics = d.bool(forKey: "showGraphics")
        selectionHints = d.bool(forKey: "selectionHints")
        tabEdge = TabEdge(rawValue: d.string(forKey: "tabEdge") ?? "") ?? .right
        tabPosition = d.double(forKey: "tabPosition")
    }
}

// MARK: - Window

struct SettingsView: View {
    @ObservedObject var p = Prefs.shared
    @State private var vocab = ""
    @State private var snippets = ""
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var status: [String: String] = [:]

    var body: some View {
        TabView {
            general.tabItem { Label("General", systemImage: "gearshape") }
            words.tabItem { Label("Vocabulary", systemImage: "textformat.abc") }
            snippetsTab.tabItem { Label("Snippets", systemImage: "text.badge.plus") }
            engines.tabItem { Label("Engines", systemImage: "waveform.badge.magnifyingglass") }
        }
        .frame(width: 560, height: 700)
        .onAppear {
            vocab = (try? String(contentsOf: Config.vocabPath, encoding: .utf8)) ?? ""
            snippets = (try? String(contentsOf: Config.snippetsPath, encoding: .utf8)) ?? ""
            Task { status = await EngineCheck.run() }
        }
    }

    var general: some View {
        Form {
            Section("Talk key") {
                Picker("Hold to talk", selection: $p.talkKey) {
                    ForEach(TalkKey.allCases) { Text($0.label).tag($0) }
                }
                Text("Hold to dictate, release to paste. Double-tap for hands-free, tap again to finish. Esc cancels.")
                    .font(.caption).foregroundStyle(.secondary)
                if p.talkKey == .fn {
                    Text("Set System Settings › Keyboard › “Press 🌐 key to” to “Do Nothing”, or macOS will open its own dictation too.")
                        .font(.caption).foregroundStyle(.orange)
                }
            }
            Section("Fix selection") {
                Toggle("Suggest Fix / Rewrite when I highlight text and pause", isOn: $p.selectionHints)
                Text("Select text anywhere, then tap ⌃⌥F to fix spelling and grammar. Hold ⌃⌥F and say how to change it (“make it shorter”), release to apply.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("On-screen tab") {
                Toggle("Show the tab on the edge of my screen", isOn: $p.showTab)
                Picker("Edge", selection: $p.tabEdge) {
                    ForEach(TabEdge.allCases) { Text($0.label).tag($0) }
                }
                .disabled(!p.showTab)
                Text("Hover it for talk, history, paste last and settings. Drag it to any edge.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Look") {
                Picker("Size", selection: $p.compactPill) {
                    Text("Compact").tag(true)
                    Text("Standard").tag(false)
                }
                .pickerStyle(.segmented)
                Toggle("Animated graphics", isOn: $p.showGraphics)
                Toggle("Show words while I talk", isOn: $p.livePreview)
                Picker("Recording pill", selection: $p.pillStyle) {
                    ForEach(PillStyle.allCases) { Text($0.label).tag($0) }
                }
                .disabled(!p.showGraphics)
                do {
                    LabeledContent("Motion when speaking") {
                        HStack {
                            Text("Calm").font(.caption).foregroundStyle(.secondary)
                            Slider(value: $p.waterMotion, in: 0...1)
                            Text("Lively").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Text("Changes apply live. Dictate something while you drag it.").font(.caption).foregroundStyle(.secondary)
                }
            }
            Section("While recording") {
                Toggle("Pause music and video", isOn: $p.pauseMedia)
                Toggle("Start and stop sounds", isOn: $p.sounds)
            }
            Section("Cleanup") {
                Toggle("Polish text with Claude Haiku", isOn: $p.polish)
                Group {
                    Toggle("Email (Mail, Spark, Superhuman)", isOn: $p.polishInEmail)
                    Toggle("Chat (Slack, Messages, WhatsApp, Discord)", isOn: $p.polishInChat)
                    Toggle("Everywhere else (browsers, docs, notes)", isOn: $p.polishElsewhere)
                    Toggle("Terminal, code editors and Claude", isOn: $p.polishInTerminal)
                }
                .padding(.leading, 18)
                .disabled(!p.polish)
                Text("Fixes filler words, punctuation, grammar and spoken lists, about a second per dictation. Where it's off you still get free filler-word removal.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section {
                Toggle("Show Dictation in the Dock", isOn: $p.showInDock)
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, on in
                        if on { try? SMAppService.mainApp.register() } else { try? SMAppService.mainApp.unregister() }
                    }
            }
        }
        .formStyle(.grouped)
    }

    var words: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Names and terms the transcriber should always spell right. One per line.")
                .font(.callout).foregroundStyle(.secondary)
            TextEditor(text: $vocab).font(.system(size: 13, design: .monospaced))
                .scrollContentBackground(.hidden).padding(6)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .textBackgroundColor)))
            HStack {
                Text("\(Config.parseVocab(vocab).count) here, plus \(Config.parseVocab((try? String(contentsOf: Config.learnedVocabPath, encoding: .utf8)) ?? "").count) learned from your History edits")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Save") { try? vocab.write(to: Config.vocabPath, atomically: true, encoding: .utf8) }
                    .keyboardShortcut("s")
            }
        }
        .padding(16)
    }

    var snippetsTab: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Say the phrase, get the text. One per line: phrase, then a TAB, then what to type.")
                .font(.callout).foregroundStyle(.secondary)
            TextEditor(text: $snippets).font(.system(size: 13, design: .monospaced))
                .scrollContentBackground(.hidden).padding(6)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .textBackgroundColor)))
            HStack { Spacer(); Button("Save") { try? snippets.write(to: Config.snippetsPath, atomically: true, encoding: .utf8) } }
        }
        .padding(16)
    }

    var engines: some View {
        Form {
            Section("Pipeline") {
                step("Transcription", status["stt"]) {
                    Picker("", selection: $p.engine) {
                        ForEach(Engine.allCases) { Text($0.label).tag($0) }
                    }
                }
                .onChange(of: p.engine) { recheck() }
                step("Cleanup", p.polish ? status["haiku"] : "filler removal only") {
                    Picker("", selection: $p.polish) {
                        Text("Claude Haiku 4.5").tag(true)
                        Text("Off").tag(false)
                    }
                }
                step("Live preview", p.livePreview ? "ready" : "off") {
                    Picker("", selection: $p.livePreview) {
                        Text("Apple on-device").tag(true)
                        Text("Off").tag(false)
                    }
                }
                step("Fallback", fallbackStatus) {
                    Picker("", selection: $p.fallback) {
                        ForEach(Fallback.allCases.filter { $0.engine != p.engine }) { Text($0.label).tag($0) }
                    }
                }
            }
            IntegrationsSection(onChange: recheck)
            Section {
                Button("Check again") { recheck() }
            }
        }
        .formStyle(.grouped)
    }

    func recheck() { status = [:]; Task { status = await EngineCheck.run() } }

    var fallbackStatus: String {
        switch p.fallback {
        case .none: return "off"
        // Apple's fallback is the live preview's own text, so it only exists while the preview runs.
        case .apple: return p.livePreview ? "ready" : "needs Live preview on"
        case .deepgram, .scribe:
            let key = p.fallback == .deepgram ? "DEEPGRAM_API_KEY" : "ELEVEN_LABS_API_KEY"
            return Config.secret(key) != nil ? "ready" : "no key, add it below"
        }
    }

    /// One pipeline step: its title on the left, the chosen tool and whether it works on the right.
    func step<P: View>(_ title: String, _ s: String?, @ViewBuilder picker: () -> P) -> some View {
        LabeledContent(title) {
            VStack(alignment: .trailing, spacing: 2) {
                picker().labelsHidden().fixedSize()
                Text(s ?? "checking…").font(.caption)
                    .foregroundStyle(s == "ready" ? .green : (s == nil || s == "off" || s == "filler removal only" ? .secondary : .orange))
            }
        }
    }
}

enum EngineCheck {
    static func run() async -> [String: String] {
        var out: [String: String] = [:]
        // Half a second of silence proves the key and plan without costing anything meaningful.
        let engine = await MainActor.run { Prefs.shared.engine }
        do { _ = try await engine.transcribe(Recorder.wav([Int16](repeating: 0, count: 8000)), keyterms: []); out["stt"] = "ready" }
        catch {
            let msg = (error as? Scribe.Failure)?.message ?? (error as? Deepgram.Failure)?.message
            out["stt"] = msg?.prefix(80).description ?? "unreachable"
        }
        out["haiku"] = await Cleanup.probe()
        return out
    }
}

@MainActor
final class SettingsWindow {
    private var window: NSWindow?
    func show() {
        if window == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 700),
                             styleMask: [.titled, .closable], backing: .buffered, defer: false)
            w.title = "Dictation Settings"
            w.isReleasedWhenClosed = false
            w.contentView = NSHostingView(rootView: SettingsView())
            w.center()
            window = w
        }
        if let w = window { AppPresence.present(w) }
    }
}


struct KeySlot: Identifiable {
    let env: String, label: String, hint: String, usedFor: String
    var id: String { env }
    static let all = [
        KeySlot(env: "DEEPGRAM_API_KEY", label: "Deepgram", hint: "console.deepgram.com → API Keys (Member role)", usedFor: "Transcription"),
        KeySlot(env: "ELEVEN_LABS_API_KEY", label: "ElevenLabs", hint: "elevenlabs.io → Developers → API Keys", usedFor: "Transcription"),
        KeySlot(env: "ANTHROPIC_API_KEY", label: "Anthropic", hint: "console.anthropic.com → API Keys", usedFor: "Cleanup"),
    ]
    var isSet: Bool { Config.secret(env) != nil }
    /// Only a key in the app's own file can be removed here; one set in the environment stays.
    var removable: Bool {
        let s = (try? String(contentsOf: Config.secretsPath, encoding: .utf8)) ?? ""
        return s.split(separator: "\n").contains { l in
            var t = l.trimmingCharacters(in: .whitespaces)
            if t.hasPrefix("export ") { t.removeFirst(7) }
            return t.hasPrefix(env + "=")
        }
    }
}

/// A listed integration has a key saved; add one from the menu, replace or remove it in its row.
struct IntegrationsSection: View {
    var onChange: () -> Void
    @State private var refresh = 0
    @State private var adding: KeySlot?

    var body: some View {
        let _ = refresh
        let listed = KeySlot.all.filter(\.isSet)
        let missing = KeySlot.all.filter { !$0.isSet && $0.id != adding?.id }
        Section {
            ForEach(listed) { k in
                IntegrationRow(slot: k) { refresh += 1; onChange() }
            }
            if let k = adding {
                KeyEntry(slot: k, onSave: { adding = nil; refresh += 1; onChange() }, onCancel: { adding = nil })
            }
            if listed.isEmpty && adding == nil {
                Text("No integrations yet.").foregroundStyle(.secondary)
            }
        } header: {
            HStack {
                Text("Integrations")
                Spacer()
                if !missing.isEmpty {
                    Menu("Add") {
                        ForEach(missing) { k in Button("\(k.label) (\(k.usedFor.lowercased()))") { adding = k } }
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                }
            }
        } footer: {
            Text("Keys are saved to ~/.dictation-secrets.env on this Mac and never shown again.")
        }
    }
}

struct IntegrationRow: View {
    let slot: KeySlot
    var onChange: () -> Void
    @State private var replacing = false

    var body: some View {
        if replacing {
            KeyEntry(slot: slot, onSave: { replacing = false; onChange() }, onCancel: { replacing = false })
        } else {
            LabeledContent {
                HStack {
                    Button("Replace") { replacing = true }
                    if slot.removable {
                        Button(role: .destructive) { Config.setSecret(slot.env, ""); onChange() } label: {
                            Image(systemName: "trash")
                        }
                        .help("Remove this key")
                    }
                }
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(slot.label)
                    Text(slot.removable ? slot.usedFor : "\(slot.usedFor) · from the environment")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }
}

/// Paste a key, press Save. The key itself is never shown.
struct KeyEntry: View {
    let slot: KeySlot
    var onSave: () -> Void
    var onCancel: () -> Void
    @State private var draft = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(slot.label)
            Text(slot.hint).font(.caption).foregroundStyle(.secondary)
            HStack {
                SecureField("Paste key", text: $draft).textFieldStyle(.roundedBorder)
                Button("Cancel", action: onCancel)
                Button("Save") {
                    guard !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                    Config.setSecret(slot.env, draft); draft = ""
                    onSave()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
    }
}
