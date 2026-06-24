import AVFoundation
import CoreAudio

/// One AVAudioEngine pinned to a specific CoreAudio output device.
/// Used twice: once for the virtual mic (BlackHole), once for headphone monitoring.
final class AudioOutput {
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private var format: AVAudioFormat?
    private var deviceID: AudioDeviceID?

    /// Re-point/reconnect only when device or format changes, then start.
    func prepare(device: AudioDeviceID, format newFormat: AVAudioFormat) throws {
        if engine.isRunning && deviceID == device && format == newFormat { return }
        engine.stop()
        engine.reset()
        if !engine.attachedNodes.contains(player) {
            engine.attach(player)
        }
        if let unit = engine.outputNode.audioUnit {
            var dev = device
            let err = AudioUnitSetProperty(
                unit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global,
                0, &dev, UInt32(MemoryLayout<AudioDeviceID>.size))
            if err != noErr { throw NSError(domain: "Narrator", code: Int(err)) }
        }
        engine.connect(player, to: engine.mainMixerNode, format: newFormat)
        format = newFormat
        deviceID = device
        engine.prepare()
        try engine.start()
    }

    /// Schedule buffers; `onLast` fires after the final one finishes playback.
    func play(_ buffers: [AVAudioPCMBuffer], onLast: (@Sendable () -> Void)? = nil) {
        for (i, buf) in buffers.enumerated() {
            let isLast = i == buffers.count - 1
            player.scheduleBuffer(buf, completionCallbackType: .dataPlayedBack) { _ in
                if isLast { onLast?() }
            }
        }
        player.play()
    }

    func stop() {
        player.stop()
    }
}
