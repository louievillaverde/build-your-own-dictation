import AVFoundation
import Speech

/// Apple's on-device streaming recognizer. Shows words in the pill while you talk and is the
/// last-resort transcript if Scribe is unreachable. Never the primary text.
@MainActor
final class LivePreview {
    private var analyzer: SpeechAnalyzer?
    private var input: AsyncStream<AnalyzerInput>.Continuation?
    private var results: Task<Void, Never>?
    private var format: AVAudioFormat?
    private var converter: AVAudioConverter?
    private(set) var finalized = ""
    private var volatile = ""
    var onUpdate: ((String) -> Void)?

    func start() async {
        finalized = ""; volatile = ""
        let t = SpeechTranscriber(locale: Locale(identifier: "en_US"), transcriptionOptions: [],
                                  reportingOptions: [.volatileResults], attributeOptions: [])
        if let req = try? await AssetInventory.assetInstallationRequest(supporting: [t]) {
            try? await req.downloadAndInstall()
        }
        let a = SpeechAnalyzer(modules: [t])
        format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [t])
        let (stream, cont) = AsyncStream<AnalyzerInput>.makeStream()
        input = cont
        analyzer = a
        results = Task { @MainActor [weak self] in
            do {
                for try await r in t.results {
                    guard let self else { return }
                    let s = String(r.text.characters)
                    if r.isFinal { self.finalized += s; self.volatile = "" } else { self.volatile = s }
                    self.onUpdate?(Self.join(self.finalized, self.volatile))
                }
            } catch {}
        }
        try? await a.start(inputSequence: stream)
    }

    /// Finalized text + the in-progress tail, dropping any words the tail repeats from the end of
    /// the finalized part (the recognizer sometimes re-sends a phrase it just committed).
    static func join(_ fin: String, _ vol: String) -> String {
        let f = fin.split(separator: " "), v = vol.split(separator: " ")
        guard !f.isEmpty, !v.isEmpty else { return (fin + vol) }
        for k in stride(from: min(f.count, v.count, 8), through: 2, by: -1)
        where f.suffix(k).map { $0.lowercased() } == v.prefix(k).map { $0.lowercased() } {
            return (f + v.dropFirst(k)).joined(separator: " ")
        }
        return fin.hasSuffix(" ") || vol.hasPrefix(" ") ? fin + vol : fin + " " + vol
    }

    /// Called from the audio thread.
    nonisolated func feed(_ buf: AVAudioPCMBuffer) {
        Task { @MainActor in self.push(buf) }
    }

    private func push(_ buf: AVAudioPCMBuffer) {
        guard let input, let format else { return }
        if buf.format == format { input.yield(AnalyzerInput(buffer: buf)); return }
        if converter == nil { converter = AVAudioConverter(from: buf.format, to: format) }
        let cap = AVAudioFrameCount(Double(buf.frameLength) * format.sampleRate / buf.format.sampleRate) + 32
        guard let converter, let out = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: cap) else { return }
        var fed = false
        converter.convert(to: out, error: nil) { _, st in
            if fed { st.pointee = .noDataNow; return nil }
            fed = true; st.pointee = .haveData; return buf
        }
        if out.frameLength > 0 { input.yield(AnalyzerInput(buffer: out)) }
    }

    func finish() async -> String {
        input?.finish()
        try? await analyzer?.finalizeAndFinishThroughEndOfInput()
        _ = await results?.value
        analyzer = nil; input = nil; converter = nil
        return (finalized + volatile).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func cancel() async {
        input?.finish()
        await analyzer?.cancelAndFinishNow()
        results?.cancel()
        analyzer = nil; input = nil; converter = nil
    }
}
