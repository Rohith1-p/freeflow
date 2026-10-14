import Foundation
import AVFoundation
import FluidAudio

struct NoteLine: Identifiable {
    let id = UUID()
    let offsetSeconds: TimeInterval
    let text: String
}

/// Continuous note-taking: mic runs until stopped, Silero VAD splits speech
/// into segments at natural pauses, and each segment is transcribed live and
/// appended as its own line. Speak → line appears. Pause → new line next.
@MainActor
final class NoteEngine: ObservableObject {
    @Published var lines: [NoteLine] = []
    @Published var isRunning = false
    @Published var isSpeaking = false
    @Published var elapsed: TimeInterval = 0

    private let engine = AVAudioEngine()
    private var sessionStart: Date?
    private var segmentBuffer: [Float] = []
    private var inSpeech = false
    private var running = false
    private var lineOffsetBase: TimeInterval = 0
    private var transcriptionChain: Task<Void, Never>?
    private var activity: NSObjectProtocol?
    private var elapsedTimer: Timer?
    private var chunkContinuation: AsyncStream<[Float]>.Continuation?

    private var vad: VadManager?
    private var vadState: VadStreamState?
    private var useVAD = false

    var transcriber: Transcriber?

    func start() async {
        guard !isRunning else { return }
        lines = []
        sessionStart = Date()
        lineOffsetBase = 0

        // Streaming VAD (Silero). Falls back to an RMS gate if unavailable.
        do {
            let manager = try await VadManager(config: VadConfig(defaultThreshold: 0.55))
            vad = manager
            vadState = await manager.makeStreamState()
            useVAD = true
        } catch {
            vad = nil
            vadState = nil
            useVAD = false
        }

        let stream = AsyncStream<[Float]> { cont in
            self.chunkContinuation = cont
        }

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        input.installTap(onBus: 0, bufferSize: 2048, format: format) { [weak self] buffer, _ in
            let samples = AudioRecorder.to16kMono(buffer: buffer, targetRate: 16000)
            self?.chunkContinuation?.yield(samples)
        }
        engine.prepare()
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            return
        }

        running = true
        isRunning = true

        // Keep the Mac awake during long note sessions
        activity = ProcessInfo.processInfo.beginActivity(
            options: [.idleSystemSleepDisabled],
            reason: "Freeflow note session")

        elapsedTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self, let start = self.sessionStart else { return }
            self.elapsed = Date().timeIntervalSince(start)
        }

        // Serial processing loop: chunks are VAD-checked strictly in order.
        let t = transcriber
        let proc = Task { [weak self] in
            for await chunk in stream {
                guard let self, self.running else { break }
                await self.handleChunk(chunk, transcriber: t)
            }
        }
        _ = proc
    }

    /// Stops the session, returns the full note text.
    func stop() -> String {
        guard isRunning else { return "" }
        running = false
        isRunning = false
        isSpeaking = false
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        chunkContinuation?.finish()
        chunkContinuation = nil
        elapsedTimer?.invalidate()
        if let activity {
            ProcessInfo.processInfo.endActivity(activity)
            self.activity = nil
        }
        // flush any pending speech segment
        let tail = segmentBuffer
        segmentBuffer = []
        inSpeech = false
        if tail.count > 8000 {
            let offset = Date().timeIntervalSince(sessionStart ?? Date()) - Double(tail.count) / 16_000
            transcribeSegment(tail, offset: max(0, offset))
        }
        return lines.map { $0.text }.joined(separator: "\n")
    }

    // MARK: - Chunk pipeline (serial: called from the processing loop)

    private func handleChunk(_ chunk: [Float], transcriber: Transcriber?) async {
        let now = Date().timeIntervalSince(sessionStart ?? Date())

        if useVAD {
            guard let vad, var st = vadState else {
                rmsHandle(chunk, now: now)
                return
            }
            do {
                let result = try await vad.processStreamingChunk(
                    chunk, state: st, config: .default, returnSeconds: true)
                st = result.state

                switch result.event?.kind {
                case .speechStart:
                    startSpeech(chunk)
                case .speechEnd:
                    if inSpeech {
                        segmentBuffer.append(contentsOf: chunk)
                        finishSegment(now)
                    }
                default:
                    if inSpeech { segmentBuffer.append(contentsOf: chunk) }
                }
            } catch {
                useVAD = false  // don't retry every chunk
                rmsHandle(chunk, now: now)
            }
        } else {
            rmsHandle(chunk, now: now)
        }
    }

    private func startSpeech(_ chunk: [Float]) {
        inSpeech = true
        segmentBuffer = chunk
        isSpeaking = true
    }

    /// RMS gate fallback: 0.6 s of quiet ends a segment.
    private func rmsHandle(_ chunk: [Float], now: Double) {
        let rms = AudioRecorder.rms(chunk) ?? 0
        if !inSpeech && rms > 0.015 {
            startSpeech(chunk)
        } else if inSpeech {
            segmentBuffer.append(contentsOf: chunk)
            let tail = segmentBuffer.suffix(9_600)  // 0.6 s
            if (AudioRecorder.rms(Array(tail)) ?? 1) < 0.008 {
                finishSegment(now)
            }
        }
    }

    private func finishSegment(_ now: Double) {
        inSpeech = false
        isSpeaking = false
        let samples = segmentBuffer
        segmentBuffer = []
        guard samples.count > 8_000 else { return }  // < 0.5 s — ignore
        let offset = max(0, now - Double(samples.count) / 16_000)
        transcribeSegment(samples, offset: offset)
    }

    private func transcribeSegment(_ samples: [Float], offset: TimeInterval) {
        // Chain transcriptions so overlapping segments stay in order.
        transcriptionChain = Task { [weak self] in
            await self?.transcriptionChain?.value
            guard let self, let text = await self.transcriber?.transcribe(samples), !text.isEmpty else { return }
            await MainActor.run {
                self.lines.append(NoteLine(offsetSeconds: offset, text: text))
            }
        }
    }
}
