import AVFoundation
import CoreAudio

/// Synthesizes text and routes the audio into a chosen output device (BlackHole),
/// so other apps can pick that device as their microphone.
/// Settings persist across launches via UserDefaults (devices stored by stable UID).
@MainActor
final class SpeechRouter: ObservableObject {

    @Published var devices: [AudioDevice] = []
    @Published var selectedDeviceID: AudioDeviceID? { didSet { save() } }   // virtual mic (BlackHole)
    @Published var monitorEnabled: Bool = false { didSet { save() } }       // hear yourself in headphones
    @Published var monitorDeviceID: AudioDeviceID? { didSet { save() } }    // headphones
    @Published var voices: [AVSpeechSynthesisVoice] = []
    @Published var selectedVoiceID: String? { didSet { save() } }
    @Published var rate: Float = AVSpeechUtteranceDefaultSpeechRate { didSet { save() } }
    @Published var isSpeaking = false
    @Published var status: String = ""

    private let micOut = AudioOutput()
    private let monitorOut = AudioOutput()
    private let synth = AVSpeechSynthesizer()
    private var pendingBuffers: [AVAudioPCMBuffer] = []
    private var loading = false   // suppress save() while restoring
    private(set) var lastSpoken: String?

    struct AudioDevice: Identifiable, Hashable {
        let id: AudioDeviceID
        let uid: String
        let name: String
    }

    private enum Key {
        static let micUID = "micUID"
        static let monitorUID = "monitorUID"
        static let monitorEnabled = "monitorEnabled"
        static let voiceID = "voiceID"
        static let rate = "rate"
    }

    init() {
        reloadDevices()
        reloadVoices()
        restore()
    }

    // MARK: - Persistence

    private func save() {
        guard !loading else { return }
        let d = UserDefaults.standard
        d.set(uid(for: selectedDeviceID), forKey: Key.micUID)
        d.set(uid(for: monitorDeviceID), forKey: Key.monitorUID)
        d.set(monitorEnabled, forKey: Key.monitorEnabled)
        d.set(selectedVoiceID, forKey: Key.voiceID)
        d.set(rate, forKey: Key.rate)
    }

    private func restore() {
        loading = true
        defer { loading = false }
        let d = UserDefaults.standard
        if let mic = d.string(forKey: Key.micUID), let id = deviceID(forUID: mic) {
            selectedDeviceID = id
        }
        if let mon = d.string(forKey: Key.monitorUID), let id = deviceID(forUID: mon) {
            monitorDeviceID = id
        }
        if d.object(forKey: Key.monitorEnabled) != nil {
            monitorEnabled = d.bool(forKey: Key.monitorEnabled)
        }
        if let v = d.string(forKey: Key.voiceID),
           voices.contains(where: { $0.identifier == v }) {
            selectedVoiceID = v
        }
        if d.object(forKey: Key.rate) != nil {
            rate = d.float(forKey: Key.rate)
        }
    }

    private func uid(for id: AudioDeviceID?) -> String? {
        guard let id else { return nil }
        return devices.first { $0.id == id }?.uid
    }

    private func deviceID(forUID uid: String) -> AudioDeviceID? {
        devices.first { $0.uid == uid }?.id
    }

    // MARK: - Voices

    func reloadVoices() {
        // Best quality first: premium > enhanced > default.
        func rank(_ v: AVSpeechSynthesisVoice) -> Int {
            switch v.quality {
            case .premium: return 0
            case .enhanced: return 1
            default: return 2
            }
        }
        let allowed: Set<String> = ["en-US", "ru-RU"]
        // ru-RU first, then en-US; within a language by quality, then name.
        func langRank(_ v: AVSpeechSynthesisVoice) -> Int { v.language == "ru-RU" ? 0 : 1 }
        let all = AVSpeechSynthesisVoice.speechVoices().filter { allowed.contains($0.language) }
        voices = all.sorted { (langRank($0), rank($0), $0.name) < (langRank($1), rank($1), $1.name) }
        if selectedVoiceID == nil || !voices.contains(where: { $0.identifier == selectedVoiceID }) {
            // Prefer a high-quality voice in the system locale.
            let loc = Locale.current.language.languageCode?.identifier == "ru" ? "ru-RU" : "en-US"
            selectedVoiceID = voices.first { $0.language == loc }?.identifier
                ?? voices.first?.identifier
        }
    }

    // MARK: - Output devices

    func reloadDevices() {
        devices = Self.outputDevices()
        if selectedDeviceID == nil || !devices.contains(where: { $0.id == selectedDeviceID }) {
            selectedDeviceID = devices.first { $0.name.localizedCaseInsensitiveContains("BlackHole") }?.id
                ?? devices.first?.id
        }
        if monitorDeviceID == nil || !devices.contains(where: { $0.id == monitorDeviceID }) {
            // Default monitor: AirPods/headphones, else built-in speakers, else first non-BlackHole.
            monitorDeviceID = devices.first { $0.name.localizedCaseInsensitiveContains("AirPods") }?.id
                ?? devices.first { $0.name.localizedCaseInsensitiveContains("Speakers") }?.id
                ?? devices.first { !$0.name.localizedCaseInsensitiveContains("BlackHole") }?.id
        }
    }

    private static func outputDevices() -> [AudioDevice] {
        var size: UInt32 = 0
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size)
        let count = Int(size) / MemoryLayout<AudioDeviceID>.size
        var ids = [AudioDeviceID](repeating: 0, count: count)
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &ids)

        return ids.compactMap { id -> AudioDevice? in
            guard outputChannelCount(id) > 0 else { return nil }
            return AudioDevice(id: id, uid: deviceUID(id), name: deviceName(id))
        }
    }

    private static func outputChannelCount(_ id: AudioDeviceID) -> Int {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioObjectPropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        AudioObjectGetPropertyDataSize(id, &addr, 0, nil, &size)
        guard size > 0 else { return 0 }
        let bufList = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: 16)
        defer { bufList.deallocate() }
        AudioObjectGetPropertyData(id, &addr, 0, nil, &size, bufList)
        let abl = bufList.assumingMemoryBound(to: AudioBufferList.self)
        let buffers = UnsafeMutableAudioBufferListPointer(abl)
        return buffers.reduce(0) { $0 + Int($1.mNumberChannels) }
    }

    private static func deviceName(_ id: AudioDeviceID) -> String {
        cfStringProperty(id, kAudioObjectPropertyName) ?? "Unknown"
    }

    /// Stable identifier that survives reboots / reconnects — unlike AudioDeviceID.
    private static func deviceUID(_ id: AudioDeviceID) -> String {
        cfStringProperty(id, kAudioDevicePropertyDeviceUID) ?? "uid-\(id)"
    }

    private static func cfStringProperty(_ id: AudioDeviceID, _ selector: AudioObjectPropertySelector) -> String? {
        var addr = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let err = AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &value)
        guard err == noErr, let cf = value?.takeRetainedValue() else { return nil }
        return cf as String
    }

    // MARK: - Speak

    func speak(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard let deviceID = selectedDeviceID else {
            status = "Нет выходного устройства"
            return
        }

        lastSpoken = trimmed

        let utterance = AVSpeechUtterance(string: trimmed)
        utterance.rate = rate
        if let vid = selectedVoiceID, let v = AVSpeechSynthesisVoice(identifier: vid) {
            utterance.voice = v
        }

        pendingBuffers.removeAll()

        // Pull PCM buffers from the synthesizer, then play them through the engine.
        synth.write(utterance) { [weak self] buffer in
            guard let self else { return }
            guard let pcm = buffer as? AVAudioPCMBuffer, pcm.frameLength > 0 else {
                // Empty buffer => synthesis finished.
                Task { @MainActor in self.flush(to: deviceID) }
                return
            }
            Task { @MainActor in self.pendingBuffers.append(pcm) }
        }
    }

    /// Re-speak the last phrase (bound to a hotkey).
    func repeatLast() {
        guard let last = lastSpoken else {
            status = "Нечего повторять"
            return
        }
        speak(last)
    }

    private func flush(to deviceID: AudioDeviceID) {
        guard let first = pendingBuffers.first else { return }
        let format = first.format
        let buffers = pendingBuffers
        pendingBuffers.removeAll()

        // Mic output (BlackHole) — required.
        do {
            try micOut.prepare(device: deviceID, format: format)
        } catch {
            status = "Mic engine: \(error.localizedDescription)"
            return
        }

        // Monitor output (headphones) — optional, never blocks the mic.
        var monitorOn = false
        if monitorEnabled, let monID = monitorDeviceID, monID != deviceID {
            do {
                try monitorOut.prepare(device: monID, format: format)
                monitorOn = true
            } catch {
                status = "Monitor: \(error.localizedDescription)"
            }
        }

        isSpeaking = true

        // Completion tracked on the mic output (always present).
        micOut.play(buffers) { [weak self] in
            Task { @MainActor in self?.isSpeaking = false }
        }
        if monitorOn { monitorOut.play(buffers) }
    }

    func stop() {
        synth.stopSpeaking(at: .immediate)
        micOut.stop()
        monitorOut.stop()
        pendingBuffers.removeAll()
        isSpeaking = false
    }
}
