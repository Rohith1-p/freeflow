import Foundation
import AVFoundation

/// Captures 16 kHz mono Float32 mic audio while active.
final class AudioRecorder {
    private let engine = AVAudioEngine()
    private(set) var samples: [Float] = []
    private(set) var isRecording = false
    private let targetRate: Double = 16_000

    var onLevel: ((Float) -> Void)?  // RMS 0...1, for UI feedback

    func start() throws {
        guard !isRecording else { return }
        samples.removeAll(keepingCapacity: true)

        let input = engine.inputNode
        let hwFormat = input.outputFormat(forBus: 0)

        // Tap at hardware rate, convert to 16k mono ourselves
        input.installTap(onBus: 0, bufferSize: 2048, format: hwFormat) { [weak self] buffer, _ in
            guard let self else { return }
            let converted = Self.to16kMono(buffer: buffer, targetRate: self.targetRate)
            self.samples.append(contentsOf: converted)
            if let onLevel = self.onLevel, let rms = Self.rms(converted) {
                onLevel(rms)
            }
        }

        engine.prepare()
        try engine.start()
        isRecording = true
    }

    /// Returns the captured samples and resets for the next recording.
    func stop() -> [Float] {
        guard isRecording else { return [] }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        isRecording = false
        return samples
    }

    // MARK: - Conversion

    private static func to16kMono(buffer: AVAudioPCMBuffer, targetRate: Double) -> [Float] {
        guard let channelPtrs = buffer.floatChannelData else { return [] }
        let frames = Int(buffer.frameLength)
        guard frames > 0 else { return [] }

        let srcRate = buffer.format.sampleRate
        let channels = Int(buffer.format.channelCount)

        // Downmix to mono first
        var mono = [Float](repeating: 0, count: frames)
        for f in 0..<frames {
            var sum: Float = 0
            for c in 0..<channels {
                sum += channelPtrs[c][f]
            }
            mono[f] = sum / Float(channels)
        }

        // Linear resample to target rate
        if abs(srcRate - targetRate) < 1 {
            return mono
        }
        let ratio = srcRate / targetRate
        let outFrames = Int(Double(frames) / ratio)
        var out = [Float](repeating: 0, count: outFrames)
        for i in 0..<outFrames {
            let pos = Double(i) * ratio
            let i0 = Int(pos)
            let frac = Float(pos - Double(i0))
            let s0 = mono[min(i0, frames - 1)]
            let s1 = mono[min(i0 + 1, frames - 1)]
            out[i] = s0 + (s1 - s0) * frac
        }
        return out
    }

    private static func rms(_ samples: [Float]) -> Float? {
        guard !samples.isEmpty else { return nil }
        var acc: Float = 0
        for s in samples { acc += s * s }
        return sqrt(acc / Float(samples.count))
    }
}
