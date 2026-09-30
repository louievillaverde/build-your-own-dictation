import AppKit
import CoreAudio

/// Pauses whatever music or video is playing while you talk, and resumes it after,
/// but only if we were the ones who paused it.
///
/// ⛔ NEVER SEND THE PLAY/PAUSE KEY ON A GUESS. It's a TOGGLE, and macOS delivers it to
/// the last "Now Playing" app, not to the app we detected. The first version sent it
/// whenever Core Audio said any player had an output open, and a silent Chrome tab
/// (a web app holding an audio context, or a video paused seconds ago) counts as open.
/// The key then landed on a PAUSED Spotify and started the music (2026-09-24).
///
/// So music apps are asked directly and told to "pause" / "play", which can never start
/// anything they weren't already doing. The key is only a fallback for browsers and other
/// players, and only when no music app is sitting there paused to catch it.
enum Media {
    private static let players: Set<String> = [
        "com.google.Chrome", "com.brave.Browser", "com.apple.Safari", "company.thebrowser.Browser",
        "org.mozilla.firefox", "com.microsoft.edgemac", "com.spotify.client", "com.apple.Music",
        "com.apple.podcasts", "com.apple.TV", "org.videolan.vlc", "com.colliderli.iina",
        "com.apple.QuickTimePlayerX", "com.tidal.desktop",
    ]
    /// Apps we can ask and command directly over Apple Events (bundle id -> app name).
    private static let musicApps: [String: String] = ["com.spotify.client": "Spotify", "com.apple.Music": "Music"]

    // State lives on `q` only, so a quick start/stop can't race a slow pause.
    private static let q = DispatchQueue(label: "com.example.dictation.media")
    private static var pausedApps: [String] = []
    /// About -50 dBFS. Real music sits far above it; an idle stream is digital silence.
    private static let audibleFloor: Float = 0.003
    private static var pausedByKey = false

    static func pauseIfPlaying() {
        guard Prefs.shared.pauseMedia else { return }
        q.async {
            pausedApps = []; pausedByKey = false
            var musicAppOpen = false
            let t0 = Date()
            for (bundle, name) in musicApps where isRunning(bundle) {
                musicAppOpen = true
                let t = Date()
                if run("tell application \"\(name)\" to player state as string") == "playing" {
                    _ = run("tell application \"\(name)\" to pause")
                    pausedApps.append(name)
                }
                debugLog("media: \(name) state check\(pausedApps.contains(name) ? " + pause" : "") \(ms(t)) ms")
            }
            // Browsers and video players (Brave, Chrome, Safari...): the toggle key is the only
            // lever, so it's pressed ONLY when a real level check hears sound coming out of
            // them. An open output stream is not sound: a tab holding an idle audio context
            // reads as "running" in silence, and pressing the toggle then STARTED the user's paused
            // music (2026-09-24). When the browser really is playing, it's the Now Playing
            // app, so the key lands on it. No sound, or no permission to listen: do nothing.
            _ = musicAppOpen
            if pausedApps.isEmpty {
                let procs = playingProcesses().filter { musicApps[$0.bundle] == nil }.map(\.id)
                let started = Date()
                let level = AudioLevel.peak(of: procs, seconds: 0.15, stopAbove: audibleFloor)
                let paused = (level ?? 0) > audibleFloor
                debugLog("media: \(procs.count) open player stream(s), level \(level.map { String(format: "%.4f", $0) } ?? "unavailable"), \(paused ? "pausing" : "leaving alone") (\(ms(started)) ms)")
                if paused {
                    sendPlayPause()
                    pausedByKey = true
                }
            }
            debugLog("media: pause step total \(ms(t0)) ms")
        }
    }

    static func resumeIfWePaused() {
        q.async {
            let apps = pausedApps, byKey = pausedByKey
            pausedApps = []; pausedByKey = false
            guard !apps.isEmpty || byKey else { return }
            // Give the user's own last word a beat to land before the music comes back.
            Thread.sleep(forTimeInterval: 0.35)
            for name in apps { _ = run("tell application \"\(name)\" to play") }
            if byKey { sendPlayPause() }
        }
    }

    private static func ms(_ since: Date) -> Int { Int(Date().timeIntervalSince(since) * 1000) }

    private static func isRunning(_ bundle: String) -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: bundle).isEmpty
    }

    /// Runs an AppleScript on `q`. Only ever called after `isRunning`, because
    /// `tell application` LAUNCHES an app that isn't open.
    private static func run(_ source: String) -> String? {
        var err: NSDictionary?
        return NSAppleScript(source: source)?.executeAndReturnError(&err).stringValue
    }

    static func playingApps() -> [String] { playingProcesses().map(\.bundle) }

    /// Player processes with an output stream open right now, with their Core Audio
    /// process objects so AudioLevel can listen to exactly those.
    static func playingProcesses() -> [(bundle: String, id: AudioObjectID)] {
        var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyProcessObjectList,
                                              mScope: kAudioObjectPropertyScopeGlobal,
                                              mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size) == noErr else { return [] }
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &ids)
        var out: [(bundle: String, id: AudioObjectID)] = []
        for id in ids {
            var a = AudioObjectPropertyAddress(mSelector: kAudioProcessPropertyIsRunningOutput,
                                               mScope: kAudioObjectPropertyScopeGlobal,
                                               mElement: kAudioObjectPropertyElementMain)
            var running: UInt32 = 0; var s = UInt32(4)
            AudioObjectGetPropertyData(id, &a, 0, nil, &s, &running)
            guard running != 0 else { continue }
            a.mSelector = kAudioProcessPropertyPID
            var pid: pid_t = 0; s = 4
            AudioObjectGetPropertyData(id, &a, 0, nil, &s, &pid)
            if pid == getpid() { continue }
            if let b = owningApp(pid)?.bundleIdentifier, players.contains(b) { out.append((b, id)) }
        }
        return out
    }

    /// Browser audio comes from a helper process; walk up to the app that owns it.
    private static func owningApp(_ pid: pid_t) -> NSRunningApplication? {
        var p = pid
        for _ in 0..<4 {
            if let app = NSRunningApplication(processIdentifier: p), app.bundleIdentifier != nil { return app }
            var info = kinfo_proc(); var len = MemoryLayout<kinfo_proc>.stride
            var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, p]
            guard sysctl(&mib, 4, &info, &len, nil, 0) == 0 else { return nil }
            p = info.kp_eproc.e_ppid
            if p <= 1 { return nil }
        }
        return nil
    }

    /// Posted straight from the media queue. It used to hop to the main thread first, and on a
    /// busy Mac that wait alone took 12.7s before the music paused (2026-09-25).
    private static func sendPlayPause() {
        let NX_KEYTYPE_PLAY: Int = 16
        for down in [true, false] {
            let flags = NSEvent.ModifierFlags(rawValue: down ? 0xA00 : 0xB00)
            let data1 = (NX_KEYTYPE_PLAY << 16) | ((down ? 0xA : 0xB) << 8)
            NSEvent.otherEvent(with: .systemDefined, location: .zero, modifierFlags: flags, timestamp: 0,
                               windowNumber: 0, context: nil, subtype: 8, data1: data1, data2: -1)?
                .cgEvent?.post(tap: .cghidEventTap)
        }
    }
}
