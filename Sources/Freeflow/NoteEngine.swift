import Foundation
import AVFoundation
import FluidAudio

struct NoteLine: Identifiable, Codable {
    let id: UUID
    let offsetSeconds: TimeInterval
    let text: String

    init(id: UUID = UUID(), offsetSeconds: TimeInterval, text: String) {
        self.id = id
        self.offsetSeconds = offsetSeconds
        self.text = text
    }
}

/// A saved note-taking session.
struct NoteSession: Identifiable, Codable {
    let id: UUID
    let startedAt: Date
    let durationSeconds: Double
    let lines: [NoteLine]

    var fullText: String { lines.map(\.text).joined(separator: "\n") }
    var preview: String { lines.first?.text ?? "(empty)" }
    var wordCount: Int {
        lines.reduce(0) { $0 + $1.text.split(separator: " ").count }
    }
}

/// Continuous note-taking. Mic runs until stopped; Silero VAD is fed in exact
/// `VadManager.chunkSize` windows (4096 samples — the model pads/truncates to
/// that size, so feeding arbitrary sizes corrupts its event timeline); each
/// speech-end boundary emits a chunk that is transcribed live and appended
/// as its own line. Speak → line appears at each pause.
@MainActor
final class NoteEngine: ObservableObject {
    @Published var lines: [NoteLine] = []
    @Published var isRunning = false
    @Published var isSpeaking = false
    @Published var elapsed: TimeInterval = 0

    private let engine = AVAudioEngine()
    private(set) var sessionStart: Date?
    var sessionStartedAt: Date? { sessionStart }
    private var running = false
    private var transcriptionChain: Task<Void, Never>?
    private var activity: NSObjectProtocol?
    private var elapsedTimer: Timer?
    private var chunkContinuation: AsyncStream<[Float]>.Continuation?

    // VAD pipeline (lockstep windows, absolute sample accounting)
    private var vad: VadManager?
    private var vadState: VadStreamState?
    private var pendingVAD: [Float] = []    // staged, not yet VAD-examined
    private var examined: [Float] = []      // VAD-examined, not yet emitted
    private var samplesFed = 0              // absolute samples given to VAD
    private var lastEmitted = 0             // absolute start of next chunk
    private var sawSpeech = false
    private var windowCount = 0
    private var vadErrors = 0
    private var fellBackToFixed = false

    private static let sampleRate = 16_000
    private static let vadWindow = VadManager.chunkSize      // 4096
    private static let minChunk = sampleRate                  // 1.0 s
    private static let maxChunk = 10 * sampleRate             // force-emit
    private static let forceTail = sampleRate / 4             // 0.25 s overlap
    private static let fixedWindow = 5 * sampleRate           // fallback
    private static let fixedEmit = 4 * sampleRate             // 1 s overlap

    var transcriber: Transcriber?

    func start() async {
        guard !isRunning else { return }
        lines = []
        sessionStart = Date()

        if let manager = try? await VadManager(config: VadConfig(defaultThreshold: 0.55)) {
            vad = manager
            vadState = await manager.makeStreamState()
        } else {
            vad = nil
            vadState = nil
        }

        pendingVAD = []
        examined = []
        samplesFed = 0
        lastEmitted = 0
        sawSpeech = false
        vadErrors = 0
        fellBackToFixed = (vad == nil || vadState == nil)
        LogFile.log("start: vad=\(vad != nil) fallback=\(fellBackToFixed) transcriber=\(transcriber != nil)")

        let stream = AsyncStream<[Float]> { cont in
            self.chunkContinuation = cont
        }

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        input.installTap(onBus: 0, bufferSize: 2048, format: format) { [weak self] buffer, _ in
            let samples = AudioRecorder.to16kMono(buffer: buffer, targetRate: 16_000)
            self?.chunkContinuation?.yield(samples)
        }
        engine.prepare()
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            LogFile.log("mic error: \(error.localizedDescription)")
            return
        }

        running = true
        isRunning = true

        activity = ProcessInfo.processInfo.beginActivity(
            options: [.idleSystemSleepDisabled],
            reason: "Freeflow note session")

        elapsedTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self, let start = self.sessionStart else { return }
            self.elapsed = Date().timeIntervalSince(start)
        }

        let t = transcriber
        Task { [weak self] in
            for await chunk in stream {
                guard let self, self.running else { break }
                await self.ingest(chunk, transcriber: t)
            }
        }
    }

    /// Stops the session, returns the saved lines.
    func stop() -> [NoteLine] {
        guard isRunning else { return [] }
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
        // flush any in-flight speech segment (never plain trailing silence)
        if sawSpeech {
            let offset = TimeInterval(lastEmitted) / Double(Self.sampleRate)
            let segment = examined
            examined = []
            lastEmitted = samplesFed
            if segment.count >= Self.minChunk / 2 {  // accept shorter final tails
                transcribeSegment(segment, offset: offset)
            }
        }
        return lines
    }

    // MARK: - Ingest (serial; called only from the processing loop)

    private func ingest(_ chunk: [Float], transcriber: Transcriber?) async {
        pendingVAD.append(contentsOf: chunk)

        if fellBackToFixed {
            fixedDrain()
            return
        }

        while pendingVAD.count >= Self.vadWindow {
            let window = Array(pendingVAD.prefix(Self.vadWindow))
            pendingVAD.removeFirst(Self.vadWindow)
            examined.append(contentsOf: window)
            samplesFed += window.count

            guard let vad, let state = vadState else { continue }
            do {
                let result = try await vad.processStreamingChunk(
                    window, state: state, config: .default)
                vadState = result.state
                vadErrors = 0

                windowCount += 1
                if windowCount % 10 == 0 {
                    LogFile.log("windows=\(windowCount) prob=\(String(format: "%.3f", result.probability)) inSpeech=\(isSpeaking) buf=\(examined.count)")
                }
                switch result.event?.kind {
                case .speechStart:
                    sawSpeech = true
                    isSpeaking = true
                    LogFile.log("speechStart @\(result.event?.sampleIndex ?? -1)")
                case .speechEnd:
                    isSpeaking = false
                    LogFile.log("speechEnd @\(result.event?.sampleIndex ?? -1)")
                    if let event = result.event {
                        let cut = min(event.sampleIndex, samplesFed)
                        emitUpTo(cut)
                    }
                default:
                    break
                }

                // never let a single line run past maxChunk
                if examined.count >= Self.maxChunk {
                    forceEmit()
                }
            } catch {
                vadErrors += 1
                if vadErrors >= 3 {
                    fellBackToFixed = true
                    LogFile.log("VAD failed 3x — fallback to fixed windows")
                }
            }
        }
    }

    /// Emits `[lastEmitted, cut)` as one transcribed line (retroactive cut).
    private func emitUpTo(_ absoluteCut: Int) {
        let length = absoluteCut - lastEmitted
        guard length >= Self.minChunk, length <= examined.count else { return }
        let segment = Array(examined.prefix(length))
        examined.removeFirst(length)
        lastEmitted = absoluteCut
        sawSpeech = false
        LogFile.log("emit segment: \(segment.count) samples")
        let offset = TimeInterval(lastEmitted - segment.count) / Double(Self.sampleRate)
        transcribeSegment(segment, offset: offset)
    }

    /// Force cut at maxChunk, keeping a short overlap tail for word continuity.
    private func forceEmit() {
        guard examined.count > Self.forceTail else { return }
        let emitLength = examined.count - Self.forceTail
        let segment = Array(examined.prefix(emitLength))
        examined.removeFirst(emitLength)
        lastEmitted += emitLength
        let offset = TimeInterval(lastEmitted - segment.count) / Double(Self.sampleRate)
        transcribeSegment(segment, offset: offset)
    }

    /// Degraded mode: fixed windows with overlap, no VAD.
    private func fixedDrain() {
        while examined.count >= Self.fixedWindow {
            let segment = Array(examined.prefix(Self.fixedEmit))
            examined.removeFirst(Self.fixedEmit)
            lastEmitted += Self.fixedEmit
            let offset = TimeInterval(lastEmitted - segment.count) / Double(Self.sampleRate)
            transcribeSegment(segment, offset: offset)
        }
    }

    private func transcribeSegment(_ samples: [Float], offset: TimeInterval) {
        // Capture the PREVIOUS chain before overwriting — awaiting
        // `transcriptionChain` inside the new task would await ITSELF
        // (the property is reassigned to this very Task) and deadlock.
        let previous = transcriptionChain
        transcriptionChain = Task { [weak self] in
            await previous?.value
            guard let self, let raw = await self.transcriber?.transcribe(samples) else { return }
            let cleaned = TextCleaner.clean(raw, removeFillers: Store.shared.settings.removeFillers)
            LogFile.log("transcribed: \(cleaned.prefix(60))")
            guard !cleaned.isEmpty else { return }
            await MainActor.run {
                self.lines.append(NoteLine(offsetSeconds: offset, text: cleaned))
            }
        }
    }
}
