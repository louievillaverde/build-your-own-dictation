import AVFoundation

/// Captures the mic as 16 kHz mono Int16, writes it to disk as it arrives, and cuts
/// chunks at natural pauses so they can be transcribed while the speaker keeps talking.
final class Recorder {
    private let engine = AVAudioEngine()
    private var converter: AVAudioConverter?
    private let outFormat = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: Config.sampleRate,
                                          channels: 1, interleaved: true)!
    private var file: AVAudioFile?
    private let lock = NSLock()
    private var samples: [Int16] = []
    private var chunkStart = 0
    private var quietSamples = 0

    /// Level 0...1 for the waveform, called on the audio thread.
    var onLevel: ((Float) -> Void)?
    /// A finished chunk (WAV bytes, sequence index), called on the audio thread.
    var onChunk: ((Data, Int) -> Void)?
    /// Every converted buffer, for the live on-device preview.
    var onBuffer: ((AVAudioPCMBuffer) -> Void)?
    private var chunkIndex = 0

    var duration: Double { lock.lock(); defer { lock.unlock() }; return Double(samples.count) / Config.sampleRate }

    func start(writingTo url: URL) throws {
        lock.lock(); samples = []; chunkStart = 0; quietSamples = 0; chunkIndex = 0; lock.unlock()
        file = try AVAudioFile(forWriting: url, settings: outFormat.settings,
                               commonFormat: .pcmFormatInt16, interleaved: true)
        let input = engine.inputNode
        let inFormat = input.outputFormat(forBus: 0)
        converter = AVAudioConverter(from: inFormat, to: outFormat)
        input.installTap(onBus: 0, bufferSize: 1024, format: inFormat) { [weak self] buf, _ in
            self?.handle(buf)
        }
        engine.prepare()
        try engine.start()
    }

    private func handle(_ buf: AVAudioPCMBuffer) {
        guard let converter else { return }
        let ratio = Config.sampleRate / buf.format.sampleRate
        let cap = AVAudioFrameCount(Double(buf.frameLength) * ratio) + 32
        guard let out = AVAudioPCMBuffer(pcmFormat: outFormat, frameCapacity: cap) else { return }
        var fed = false
        var err: NSError?
        converter.convert(to: out, error: &err) { _, status in
            if fed { status.pointee = .noDataNow; return nil }
            fed = true; status.pointee = .haveData; return buf
        }
        guard out.frameLength > 0, let ch = out.int16ChannelData?[0] else { return }
        let n = Int(out.frameLength)
        try? file?.write(from: out)
        onBuffer?(out)

        var sum: Float = 0
        for i in 0..<n { let v = Float(ch[i]) / 32768; sum += v * v }
        let rms = sqrt(sum / Float(n))
        onLevel?(min(1, rms * 12))

        lock.lock()
        samples.append(contentsOf: UnsafeBufferPointer(start: ch, count: n))
        quietSamples = rms < 0.012 ? quietSamples + n : 0
        let pending = samples.count - chunkStart
        var cut: (Data, Int)?
        if Double(pending) >= Config.chunkMinSeconds * Config.sampleRate,
           Double(quietSamples) >= Config.chunkPauseSeconds * Config.sampleRate {
            cut = (Recorder.wav(Array(samples[chunkStart..<samples.count])), chunkIndex)
            chunkStart = samples.count; chunkIndex += 1
        }
        lock.unlock()
        if let cut { onChunk?(cut.0, cut.1) }
    }

    /// Stops capture and returns the untranscribed tail plus its index.
    func stop() -> (tail: Data?, index: Int) {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        file = nil // closes and finalizes the WAV header
        lock.lock(); defer { lock.unlock() }
        let rest = Array(samples[chunkStart..<samples.count])
        // Under ~0.3s of new audio is breath, not speech.
        return (rest.count > Int(0.3 * Config.sampleRate) ? Recorder.wav(rest) : nil, chunkIndex)
    }

    func fullWAV() -> Data { lock.lock(); defer { lock.unlock() }; return Recorder.wav(samples) }

    static func wav(_ s: [Int16]) -> Data {
        var d = Data()
        func u32(_ v: UInt32) { var x = v.littleEndian; d.append(Data(bytes: &x, count: 4)) }
        func u16(_ v: UInt16) { var x = v.littleEndian; d.append(Data(bytes: &x, count: 2)) }
        let bytes = UInt32(s.count * 2)
        d.append("RIFF".data(using: .ascii)!); u32(36 + bytes); d.append("WAVE".data(using: .ascii)!)
        d.append("fmt ".data(using: .ascii)!); u32(16); u16(1); u16(1)
        u32(UInt32(Config.sampleRate)); u32(UInt32(Config.sampleRate) * 2); u16(2); u16(16)
        d.append("data".data(using: .ascii)!); u32(bytes)
        s.withUnsafeBufferPointer { d.append(Data(buffer: $0)) }
        return d
    }
}
