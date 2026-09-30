import CoreAudio
import Foundation

/// Measures how loud specific processes are RIGHT NOW, by tapping their output for a
/// fraction of a second (a Core Audio process tap, macOS 14.2+).
///
/// Why this exists: "has an output stream open" is not "is making sound". A browser tab
/// holding an idle audio context keeps its stream open in silence, and Dictation used to
/// treat that as playing, press the Play/Pause toggle, and START paused music
/// (2026-09-24, Brave). A real level check is the only honest answer to "is it playing?".
///
/// Needs the "System Audio Recording" permission (NSAudioCaptureUsageDescription). If
/// it's denied, or any step fails, this returns nil and the caller must NOT pause: a
/// missed pause is harmless, a wrong toggle starts music.
enum AudioLevel {
    /// Peak sample (0...1) across `processes` over `seconds`, or nil if we couldn't listen.
    /// Returns as soon as one buffer crosses `stopAbove`, so playing music is caught in the
    /// first ~10ms of audio instead of after the whole window (pausing felt slow).
    static func peak(of processes: [AudioObjectID], seconds: Double = 0.2, stopAbove: Float = .infinity) -> Float? {
        guard !processes.isEmpty, let outputUID = defaultOutputUID() else { return nil }

        let desc = CATapDescription(stereoMixdownOfProcesses: processes)
        desc.uuid = UUID()
        desc.isPrivate = true
        desc.muteBehavior = .unmuted
        var tapID = AudioObjectID(kAudioObjectUnknown)
        guard AudioHardwareCreateProcessTap(desc, &tapID) == noErr, tapID != kAudioObjectUnknown else { return nil }
        defer { AudioHardwareDestroyProcessTap(tapID) }

        let agg: [String: Any] = [
            kAudioAggregateDeviceNameKey: "Dictation level check",
            kAudioAggregateDeviceUIDKey: UUID().uuidString,
            kAudioAggregateDeviceMainSubDeviceKey: outputUID,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: outputUID]],
            kAudioAggregateDeviceTapListKey: [[kAudioSubTapDriftCompensationKey: true,
                                               kAudioSubTapUIDKey: desc.uuid.uuidString]],
        ]
        var aggID = AudioObjectID(kAudioObjectUnknown)
        guard AudioHardwareCreateAggregateDevice(agg as CFDictionary, &aggID) == noErr else { return nil }
        defer { AudioHardwareDestroyAggregateDevice(aggID) }

        let lock = NSLock()
        var peak: Float = 0
        var gotAudio = false
        var signalled = false
        let heard = DispatchSemaphore(value: 0)
        var procID: AudioDeviceIOProcID?
        let status = AudioDeviceCreateIOProcIDWithBlock(&procID, aggID, nil) { _, inData, _, _, _ in
            let list = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: inData))
            var local: Float = 0
            for buf in list {
                guard let data = buf.mData else { continue }
                let n = Int(buf.mDataByteSize) / MemoryLayout<Float>.size
                let samples = data.assumingMemoryBound(to: Float.self)
                for i in 0..<n { local = max(local, abs(samples[i])) }
            }
            lock.lock(); peak = max(peak, local); gotAudio = true
            let fire = peak > stopAbove && !signalled; if fire { signalled = true }
            lock.unlock()
            if fire { heard.signal() }
        }
        guard status == noErr, let proc = procID else { return nil }
        defer { AudioDeviceDestroyIOProcID(aggID, proc) }
        guard AudioDeviceStart(aggID, proc) == noErr else { return nil }
        _ = heard.wait(timeout: .now() + seconds)
        AudioDeviceStop(aggID, proc)

        lock.lock(); defer { lock.unlock() }
        return gotAudio ? peak : nil
    }

    private static func defaultOutputUID() -> String? {
        var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                                              mScope: kAudioObjectPropertyScopeGlobal,
                                              mElement: kAudioObjectPropertyElementMain)
        var dev = AudioObjectID(kAudioObjectUnknown); var size = UInt32(MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &dev) == noErr else { return nil }
        addr.mSelector = kAudioDevicePropertyDeviceUID
        var uid: Unmanaged<CFString>?; size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(dev, &addr, 0, nil, &size, &uid) == noErr, let u = uid else { return nil }
        return u.takeRetainedValue() as String
    }
}
