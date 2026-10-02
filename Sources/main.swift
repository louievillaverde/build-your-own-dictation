import AppKit
import AVFoundation
import ServiceManagement

@MainActor
final class Controller: NSObject {
    let overlay = Overlay()
    let history = HistoryWindow()
    let hotkeys = Hotkeys()
    let live = LivePreview()
    let settings = SettingsWindow()
    let tab = EdgeTab()
    let notes = NotesWindow()
    let hint = SelectionHint()
    private var recorder: Recorder?
    private var statusItem: NSStatusItem!
    private var tickTimer: Timer?

    // Current session
    private var sessionId = ""
    private var startedAt = Date()
    private var wavURL: URL?
    private var appId = ""
    private var appName = ""
    private var handsFree = false
    private var chunks: [Int: Task<String?, Never>] = [:]
    private var sessionEngine: Engine = .deepgram
    private var busy = false
    enum Mode { case dictate, fixInstruction }
    private var mode: Mode = .dictate
    /// The text that was selected when a spoken fix instruction started.
    private var fixTarget: String?

    var isRecording: Bool { recorder != nil }

    func launch() {
        Config.ensureDirs()
        seedFiles()
        setupMenu()
        live.onUpdate = { [weak self] s in self?.overlay.model.live = s }
        hotkeys.isRecording = { [weak self] in MainActor.assumeIsolated { self?.isRecording ?? false } }
        hotkeys.isHandsFree = { [weak self] in MainActor.assumeIsolated { (self?.isRecording ?? false) && (self?.handsFree ?? false) } }
        hotkeys.handler = { [weak self] e in
            MainActor.assumeIsolated {
                guard let self else { return }
                switch e {
                case .startHold: self.start(handsFree: false)
                case .startHandsFree: self.start(handsFree: true)
                case .fixSelection: self.fixSelection(instruction: nil)
                case .startFixInstruction: self.startFixInstruction()
                case .finish: self.finish()
                case .cancel: self.cancel()
                case .pasteLast: self.pasteLast()
                case .history: self.history.show()
                }
            }
        }
        AVCaptureDevice.requestAccess(for: .audio) { _ in }
        // Scriptable trigger for smoke tests: `dictatectl start|finish|cancel`.
        let dnc = DistributedNotificationCenter.default()
        for (name, action) in [("start", { self.start(handsFree: true) }), ("finish", { self.finish() }),
                               ("cancel", { self.cancel() }), ("history", { self.history.show() }), ("settings", { self.settings.show() }), ("notes", { self.notes.show() }), ("pilldemo", { self.pillDemo() }), ("pillcycle", { self.pillCycle() }), ("pillstates", { self.pillStates() }),
                               ("tabdemo", { self.tab.notifyUnpasted(true); self.tab.preview(hover: 4) }),
                               ("tabreset", { self.tab.preview(hover: nil); self.tab.notifyUnpasted(false) })] as [(String, () -> Void)] {
            dnc.addObserver(forName: .init("com.example.dictation.\(name)"), object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { action() }
            }
        }
        installHotkeysWhenTrusted(prompt: true)
        // Start with the Mac, once, by default; switching it off in Settings sticks.
        if !UserDefaults.standard.bool(forKey: "didAutoEnableLogin") {
            try? SMAppService.mainApp.register()
            UserDefaults.standard.set(true, forKey: "didAutoEnableLogin")
            debugLog("login item: \(SMAppService.mainApp.status.rawValue)")
        }
        tab.model.onTalk = { [weak self] in
            guard let self else { return }
            if self.isRecording { self.finish() } else { self.start(handsFree: true) }
        }
        tab.model.onFix = { [weak self] in self?.fixSelection(instruction: nil) }
        tab.model.onNotes = { [weak self] in self?.notes.show() }
        tab.model.onMore = { [weak self] in
            guard let self else { return }
            self.tab.showMoreMenu(fix: { self.fixSelection(instruction: nil) },
                                  pasteLast: { self.pasteLast() },
                                  settings: { self.settings.show() })
        }
        notes.model.onDictate = { [weak self] in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { self?.start(handsFree: true) }
        }
        hint.onFix = { [weak self] in self?.fixSelection(instruction: nil) }
        hint.onRewrite = { [weak self] in self?.startFixInstruction(handsFree: true) }
        hint.suppressed = { [weak self] in
            guard let self else { return true }
            return self.isRecording || self.busy || NSWorkspace.shared.frontmostApplication?.bundleIdentifier == Bundle.main.bundleIdentifier
        }
        hint.start()
        overlay.onHidden = { [weak self] in self?.tab.setRecording(false) }
        tab.model.onHistory = { [weak self] in self?.history.show() }
        tab.model.onPasteLast = { [weak self] in self?.pasteLast() }
        tab.model.onSettings = { [weak self] in self?.settings.show() }
        tab.refresh()
    }

    private func installHotkeysWhenTrusted(prompt: Bool) {
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: prompt] as CFDictionary
        let trusted = AXIsProcessTrustedWithOptions(opts)
        let installed = trusted && hotkeys.install()
        debugLog("hotkeys: trusted=\(trusted) installed=\(installed) key=\(Prefs.shared.talkKey.rawValue)")
        if installed {
            statusItem.button?.image = symbol("waveform")
            return
        }
        statusItem.button?.image = symbol("waveform.slash")
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in self?.installHotkeysWhenTrusted(prompt: false) }
    }

    // MARK: recording

    func start(handsFree: Bool, mode: Mode = .dictate) {
        guard recorder == nil, !busy else { return }
        self.mode = mode
        Media.pauseIfPlaying() // first, so the music is already fading when the mic opens
        let front = NSWorkspace.shared.frontmostApplication
        appId = front?.bundleIdentifier ?? ""
        appName = front?.localizedName ?? ""
        sessionId = UUID().uuidString.lowercased()
        startedAt = Date()
        self.handsFree = handsFree
        chunks = [:]
        let url = Config.audioDir.appendingPathComponent("\(sessionId).wav")
        wavURL = url

        let rec = Recorder()
        let vocab = Config.vocab()
        let engine = Prefs.shared.engine
        sessionEngine = engine
        rec.onLevel = { [model = overlay.model] l in model.push(level: l) }
        let preview = Prefs.shared.livePreview
        rec.onBuffer = { [live] b in if preview { live.feed(b) } }
        rec.onChunk = { [weak self] wav, idx in
            DispatchQueue.main.async {
                self?.chunks[idx] = Task { try? await engine.transcribe(wav, keyterms: vocab) }
            }
        }
        do { try rec.start(writingTo: url) } catch {
            overlay.show(.error("Microphone unavailable"), hideAfter: 2.5); return
        }
        recorder = rec
        if Prefs.shared.livePreview { Task { await live.start() } }
        playSound("Tink")
        overlay.model.handsFree = handsFree
        overlay.model.elapsed = 0
        overlay.model.keySymbol = Prefs.shared.talkKey.short
        overlay.model.caption = mode == .fixInstruction ? "How should I change it?" : nil
        overlay.show(.listening)
        tab.setRecording(true)
        tab.notifyUnpasted(false)   // a new recording clears the "waiting to paste" glow
        statusItem.button?.image = symbol("waveform.circle.fill")
        tickTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.recorder != nil else { return }
                self.overlay.model.elapsed = Date().timeIntervalSince(self.startedAt)
                if self.overlay.model.elapsed > 20 * 60 { self.finish() }
            }
        }
    }

    func cancel() {
        guard let rec = recorder else { return }
        let dur = rec.duration
        _ = rec.stop()
        teardown()
        Media.resumeIfWePaused()
        chunks.values.forEach { $0.cancel() }
        Task { await live.cancel() }
        if let u = wavURL { try? FileManager.default.removeItem(at: u) }
        if dur < 0.5 { overlay.hide() } else { overlay.show(.error("Cancelled"), hideAfter: 1.0) }
    }

    private func teardown() {
        recorder = nil
        // The tab stays away until the bubble is gone (overlay.onHidden).
        tickTimer?.invalidate(); tickTimer = nil
        statusItem.button?.image = symbol("waveform")
    }

    func finish() {
        guard let rec = recorder else { return }
        let duration = rec.duration
        if duration < 0.5 { cancel(); return }
        let (tail, tailIdx) = rec.stop()
        let full = rec.fullWAV()
        teardown()
        Media.resumeIfWePaused()
        busy = true
        playSound("Pop")
        overlay.show(.working)
        let released = Date()
        let vocab = Config.vocab()
        let stt = sessionEngine
        if let tail { chunks[tailIdx] = Task { try? await stt.transcribe(tail, keyterms: vocab) } }
        let pending = chunks.sorted { $0.key < $1.key }.map(\.value)
        let (id, at, aId, aName, wav) = (sessionId, startedAt, appId, appName, wavURL)

        Task { @MainActor in
            async let appleText = Prefs.shared.livePreview ? live.finish() : ""
            var parts: [String] = []
            var ok = true
            for t in pending { if let s = await t.value { parts.append(s) } else { ok = false } }
            let tCloud = Int(Date().timeIntervalSince(released) * 1000)
            var raw = parts.joined(separator: " ")
            var engine = stt.rawValue
            if !ok {
                // No point re-uploading the whole take when the key or credit was refused.
                if !stt.isBenched, let s = try? await stt.transcribe(full, keyterms: vocab, timeout: 40) {
                    raw = s; engine = "\(stt.rawValue)-retry"
                } else if let fb = Prefs.shared.fallback.engine, fb != stt, !fb.isBenched,
                          let s = try? await fb.transcribe(full, keyterms: vocab, timeout: 40) {
                    raw = s; engine = "\(fb.rawValue)-fallback"
                } else if Prefs.shared.fallback != .none {
                    // Apple's live text is also the last resort when a cloud fallback fails too.
                    raw = await appleText; engine = "apple-fallback"
                }
            }
            _ = await appleText
            let tApple = Int(Date().timeIntervalSince(released) * 1000)
            raw = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !raw.isEmpty else {
                busy = false
                overlay.show(.error("Didn't catch that"), hideAfter: 1.8)
                if let wav { try? FileManager.default.removeItem(at: wav) }
                return
            }
            let latency = { Int(Date().timeIntervalSince(released) * 1000) }
            switch mode {
            case .fixInstruction:
                busy = false
                if let wav { try? FileManager.default.removeItem(at: wav) }
                fixSelection(instruction: Cleanup.stripFillers(raw), target: fixTarget)
                return
            case .dictate:
                let style = Cleanup.style(for: aId)
                let (polished, usedHaiku) = await Cleanup.polish(raw, style: style, vocab: vocab)
                let (text, files) = Attachments.expand(Cleanup.applySnippets(polished), raw: raw)
                if usedHaiku { engine += "+haiku" }
                if !files.isEmpty { engine += "+\(files.count)file" }
                let tPolish = latency()
                Store.shared.insert(id: id, at: at, appId: aId, appName: aName, duration: duration, raw: raw,
                                    text: text, engine: engine, latencyMs: tPolish, pasted: false, audioPath: wav?.path)
                deliver(text, id: id)
                debugLog("take \(String(format: "%.0f", duration))s \(engine): cloud \(tCloud) ms, apple done \(tApple) ms, polish done \(tPolish) ms, pasted \(latency()) ms (\(pending.count) chunk(s))")
            }
            busy = false
            if let wav { compress(wav, id: id) }
        }
    }

    /// Paste when there's a text box, otherwise leave it on the clipboard and say so. Never silent.
    private func deliver(_ text: String, id: String?) {
        if Paster.focusedTextTarget() == false {
            Paster.copy(text)
            overlay.show(.notice("Copied", "no text box focused · ⌘V"), hideAfter: 3.5)
            tab.notifyUnpasted(true)
        } else {
            // Picking up after existing text: "…last sentence." + "Next one" → "…last sentence. Next one"
            let spaced = Paster.needsLeadingSpace(after: Paster.characterBeforeCursor(), text: text) ? " " + text : text
            Paster.paste(spaced)
            if let id { Store.shared.setPasted(id, true) }
            tab.notifyUnpasted(false)
            overlay.show(.done(text), hideAfter: 1.4)
        }
    }


    // MARK: fix selection

    func startFixInstruction(handsFree: Bool = false) {
        guard recorder == nil, !busy else { return }
        Task { @MainActor in
            guard let sel = await Fixer.selectedText() else {
                overlay.show(.error("Select some text first"), hideAfter: 1.8); return
            }
            fixTarget = sel
            start(handsFree: handsFree, mode: .fixInstruction)
        }
    }

    func fixSelection(instruction: String?, target: String? = nil) {
        guard !busy else { return }
        busy = true
        Task { @MainActor in
            defer { busy = false }
            let sel: String?
            if let target { sel = target } else { sel = await Fixer.selectedText() }
            guard let sel else { overlay.show(.error("Select some text first"), hideAfter: 1.8); return }
            overlay.model.caption = nil
            overlay.show(.working)
            overlay.model.workingLabel = instruction == nil ? "Fixing" : "Rewriting"
            let t0 = Date()
            let (out, engine) = await Fixer.fix(sel, instruction: instruction)
            guard let out, !out.isEmpty else {
                overlay.show(.error("Couldn't fix it · nothing changed"), hideAfter: 2.2); return
            }
            let front = NSWorkspace.shared.frontmostApplication
            Store.shared.insert(id: UUID().uuidString.lowercased(), at: t0, appId: front?.bundleIdentifier ?? "",
                                appName: front?.localizedName ?? "", duration: 0, raw: sel, text: out,
                                engine: "fix:\(engine)" + (instruction.map { " (\($0))" } ?? ""),
                                latencyMs: Int(Date().timeIntervalSince(t0) * 1000), pasted: true, audioPath: nil)
            if out == sel { overlay.show(.done("Already clean"), hideAfter: 1.4); return }
            Paster.paste(out) // the selection is still active, so this replaces it
            overlay.show(.done(out), hideAfter: 1.4)
        }
    }

    func pasteLast() {
        guard let d = Store.shared.last() else { overlay.show(.error("No dictations yet"), hideAfter: 1.5); return }
        deliver(d.text, id: nil)
    }

    /// WAV → 32 kbps AAC to keep the archive small (~15 MB per hour of talking).
    private func compress(_ wav: URL, id: String) {
        let m4a = wav.deletingPathExtension().appendingPathExtension("m4a")
        DispatchQueue.global(qos: .utility).async {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/opt/homebrew/bin/ffmpeg")
            p.arguments = ["-v", "error", "-y", "-i", wav.path, "-c:a", "aac", "-b:a", "32k", m4a.path]
            guard (try? p.run()) != nil else { return }
            p.waitUntilExit()
            if p.terminationStatus == 0 {
                Store.shared.setAudioPath(id, m4a.path)
                try? FileManager.default.removeItem(at: wav)
            }
        }
    }

    private func playSound(_ name: String) {
        guard Prefs.shared.sounds, let s = NSSound(named: name) else { return }
        s.volume = 0.35
        s.play()
    }

    // MARK: menu

    private func symbol(_ name: String) -> NSImage? {
        let i = NSImage(systemSymbolName: name, accessibilityDescription: "Dictation")
        i?.isTemplate = true
        return i
    }

    private func setupMenu() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = symbol("waveform")
        let menu = NSMenu()
        menu.addItem(item("History", #selector(openHistory), "h"))
        menu.addItem(item("Paste last dictation", #selector(pasteLastAction), "v"))
        menu.addItem(item("Fix selected text", #selector(fixAction), "f"))
        menu.addItem(item("Notes", #selector(notesAction), ""))
        menu.addItem(item("Open archive folder", #selector(openArchive), ""))
        menu.addItem(.separator())
        menu.addItem(item("Settings…", #selector(openSettings), ","))
        menu.addItem(item("Quit", #selector(quit), "q"))
        statusItem.menu = menu
    }

    private func item(_ title: String, _ sel: Selector, _ key: String) -> NSMenuItem {
        let i = NSMenuItem(title: title, action: sel, keyEquivalent: key)
        if key == "h" || key == "v" || key == "f" { i.keyEquivalentModifierMask = [.control, .option] }
        i.target = self
        return i
    }

    @objc func openHistory() { history.show() }
    @objc func pasteLastAction() { pasteLast() }
    @objc func fixAction() { fixSelection(instruction: nil) }
    @objc func notesAction() { notes.show() }
    func reopened() { settings.show() }

    /// Smoke test: every non-listening message the pill can show, 3s each, for layout checks.
    func pillStates() {
        let states: [OverlayModel.Phase] = [
            .working, .done("Short take pasted"), .error("Cancelled"), .error("Didn't catch that"),
            .notice("Copied", "no text box focused · ⌘V"), .done("Already clean"),
        ]
        for (i, st) in states.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 3) {
                self.overlay.show(st, hideAfter: i == states.count - 1 ? 3 : nil)
            }
        }
    }

    /// Smoke test: listening → transcribing → pasted, the full cycle, no recording.
    func pillCycle() {
        pillDemo()
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            self.overlay.show(.working)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
                self.overlay.show(.done("After the transcription is done, it takes the words I'm saying and shows them here in the pill."), hideAfter: 2.5)
            }
        }
    }

    /// Smoke test: shows the listening pill with fake words and a fake voice for 8s, no recording.
    func pillDemo() {
        overlay.model.live = "I really like being able to see the words as I'm saying them"
        overlay.model.elapsed = 17
        overlay.model.caption = nil
        overlay.model.handsFree = false
        overlay.show(.listening, hideAfter: 8)
        let t0 = Date()
        let words = "I really like being able to see the words as I'm saying them because it helps me catch mistakes early".split(separator: " ")
        Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [model = overlay.model] timer in
            let e = Date().timeIntervalSince(t0)
            let n = min(words.count, 3 + Int(e / 0.18))
            MainActor.assumeIsolated { model.live = words.prefix(n).joined(separator: " ") }
            model.push(level: Float(0.35 + 0.35 * abs(sin(e * 5.3)) * abs(sin(e * 1.7 + 1))))
            if e > 8 { timer.invalidate() }
        }
    }
    @objc func openArchive() { NSWorkspace.shared.open(Config.daysDir) }
    @objc func openSettings() { settings.show() }
    @objc func quit() { NSApp.terminate(nil) }

    private func seedFiles() {
        let fm = FileManager.default
        if !fm.fileExists(atPath: Config.vocabPath.path) {
            try? """
            # One term per line. Sent to the transcriber so these come out spelled right.
            # Replace these examples with your own: your name, your company, your clients, your tools.
            Claude Code
            Deepgram
            ElevenLabs
            GitHub
            macOS
            """.write(to: Config.vocabPath, atomically: true, encoding: .utf8)
        }
        if !fm.fileExists(atPath: Config.snippetsPath.path) {
            try? "# spoken phrase<TAB>what gets typed\n# my email address\tyou@example.com\n"
                .write(to: Config.snippetsPath, atomically: true, encoding: .utf8)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    var controller: Controller?
    /// Opening Dictation again (Spotlight, Finder, Dock) while it runs shows Settings,
    /// since the menu bar icon can end up hidden behind the notch.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        MainActor.assumeIsolated { controller?.reopened() }
        return false
    }

    func applicationDidFinishLaunching(_ n: Notification) {
        MainActor.assumeIsolated {
            let c = Controller()
            controller = c
            c.launch()
        }
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
Prefs.applyDockPolicy()
app.run()
