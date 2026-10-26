import Foundation
import AppKit
import FluidAudio
import Combine

/// Coordinates hotkey → record → transcribe → paste → history.
@MainActor
final class AppState: ObservableObject {
    @Published var isRecording = false
    @Published var keyIsDown = false
    @Published var lastText: String?
    @Published var lastError: String?

    let store = Store.shared
    let transcriber = Transcriber()
    let overlay = RecordingOverlay()
    let notes = NoteEngine()
    private let recorder = AudioRecorder()
    private let hotkey = HotkeyMonitor()
    private var recordStart = Date()
    private var transcriptionTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()

    init() {
        // Forward child-object changes (note engine, model state) so every
        // view observing AppState re-renders — e.g. the live-session card
        // appearing the instant a note session starts.
        notes.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
        transcriber.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
    }

    func startEngine() {
        hotkey.onKeyDown = { [weak self] in self?.hotkeyDown() }
        hotkey.onKeyUp = { [weak self] in self?.hotkeyUp() }
        hotkey.start(keyCodes: [store.settings.hotkeyKeyCode])

        // Live mic level for the overlay (audio thread → main hop)
        recorder.onLevel = { [weak self] rms in
            DispatchQueue.main.async {
                self?.overlay.updateLevel(rms)
            }
        }

        if !hotkey.isActive {
            // Accessibility/Input Monitoring not granted yet. macOS KILLS the
            // app when the user grants Input Monitoring — install a watchdog
            // that relaunches us if we disappear, so onboarding continues.
            installRelaunchWatchdog()
            retryTapUntilActive()
        }
    }

    /// If the app is killed by the system (permission grant), reopen it.
    private func installRelaunchWatchdog() {
        let appPath = Bundle.main.bundlePath
        let script = """
        for i in $(seq 1 24); do
            sleep 5
            if ! pgrep -x Freeflow >/dev/null; then
                open "\(appPath)"
                exit 0
            fi
        done
        """
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c", script]
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        try? p.run()
    }

    /// Retry creating the event tap until the permission lands.
    private func retryTapUntilActive() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            guard let self, !self.hotkey.isActive else { return }
            self.hotkey.start(keyCodes: [self.store.settings.hotkeyKeyCode])
            self.retryTapUntilActive()
        }
    }

    func restartHotkey() {
        hotkey.start(keyCodes: [store.settings.hotkeyKeyCode])
    }

    var hotkeyActive: Bool { hotkey.isActive }

    /// Forces the macOS microphone permission prompt by actually opening the
    /// input for a moment. `requestRecordPermission` alone does not reliably
    /// show the prompt for this app; engine start always does.
    func pokeMicrophone() {
        guard !isRecording else { return }
        try? recorder.start()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            guard let self, !self.isRecording else { return }
            _ = self.recorder.stop()
        }
    }

    // MARK: - Freeflow speech (live streaming mode)

    @Published var isStreaming = false
    @Published var streamingWords = 0
    private var streamingText = ""
    private var streamDecoder: TdtDecoderState?
    private var streamTimer: Timer?
    private var streamStart: Date?
    private var streamProcessedSamples = 0
    private var sliceInFlight = false
    private var lastHotkeyTap: Date?

    /// Double-tap detection lives here: in Freeflow mode a double-tap toggles
    /// streaming on/off; in Hold mode the down/up pair behaves as normal.
    func hotkeyDown() {
        keyIsDown = true
        let now = Date()

        if notes.isRunning { return }   // note session owns the mic

        if store.settings.inputMode == .freeflowSpeech {
            if isStreaming {
                // second tap of a double-tap pair stops streaming
                if let last = lastHotkeyTap, now.timeIntervalSince(last) < 0.5 {
                    lastHotkeyTap = nil
                    stopFreeflowSpeech()
                } else {
                    lastHotkeyTap = now
                }
            } else {
                if let last = lastHotkeyTap, now.timeIntervalSince(last) < 0.5 {
                    lastHotkeyTap = nil
                    startFreeflowSpeech()
                } else {
                    lastHotkeyTap = now
                }
            }
            return
        }
        beginDictation()
    }

    func hotkeyUp() {
        keyIsDown = false
        guard store.settings.inputMode == .holdAndSpeak else { return }
        endDictation()
    }

    func startFreeflowSpeech() {
        guard transcriber.isReady, !isStreaming, !notes.isRunning else { return }
        isStreaming = true
        streamingText = ""
        streamingWords = 0
        streamProcessedSamples = 0
        streamStart = Date()
        streamDecoder = try? TdtDecoderState()
        overlay.showStreaming(key: KeyNames.name(forCode: store.settings.hotkeyKeyCode))
        try? recorder.start()
        streamTimer = Timer.scheduledTimer(withTimeInterval: 2.5, repeats: true) { [weak self] _ in
            self?.transcribeStreamSlice()
        }
    }

    func stopFreeflowSpeech() {
        guard isStreaming else { return }
        isStreaming = false
        streamTimer?.invalidate()
        streamTimer = nil
        let duration = Date().timeIntervalSince(streamStart ?? Date())
        let all = recorder.stop()

        // transcribe the final tail (< 2.5 s since the last slice)
        let tailCount = max(0, all.count - streamProcessedSamples)
        let tail = tailCount > 16_000 ? Array(all[streamProcessedSamples...]) : []

        Task { [weak self] in
            guard let self else { return }
            // Only the UNPYPED tail goes to the cursor — live slices were
            // already typed as they came. Re-typing the full session caused
            // everything to appear twice.
            if !tail.isEmpty, var tailDecoder = self.streamDecoder,
               let tailDecoded = await self.transcriber.transcribeSlice(tail, decoder: &tailDecoder) {
                let t = self.store.settings.removeFillers ? TextCleaner.stripFillers(tailDecoded) : tailDecoded
                if !t.isEmpty {
                    let sep = self.streamingText.isEmpty || self.streamingText.hasSuffix(" ") ? "" : " "
                    Typer.type(sep + t)
                    self.streamingText += (sep.isEmpty ? "" : " ") + t
                }
            }
            let cleaned = TextCleaner.stripLeadingPunctuation(
                self.streamingText.trimmingCharacters(in: .whitespacesAndNewlines))
            if !cleaned.isEmpty {
                let frontApp = NSWorkspace.shared.frontmostApplication?.localizedName
                self.store.add(text: cleaned, duration: duration, app: frontApp)
            }
            self.overlay.hide()
        }
    }
    private var streamTailDecoder: TdtDecoderState?

    private func transcribeStreamSlice() {
        guard isStreaming, !sliceInFlight else { return }
        let all = recorder.samples
        let newCount = all.count - streamProcessedSamples
        guard newCount >= 24_000 else { return }  // ≥ 1.5 s of new audio
        sliceInFlight = true

        // Cut at a silence boundary so words never split across slices.
        let cut = Self.silenceCut(in: all, from: streamProcessedSamples)
        guard cut - streamProcessedSamples >= 16_000 else {  // need ≥ 1 s usable
            sliceInFlight = false
            return
        }
        let slice = Array(all[streamProcessedSamples..<cut])
        streamProcessedSamples = cut   // remainder after the cut rolls into the next slice
        let removeFillers = store.settings.removeFillers

        Task { [weak self] in
            guard let self, var dec = self.streamDecoder else {
                await MainActor.run { self?.sliceInFlight = false }
                return
            }
            let text = await self.transcriber.transcribeSlice(slice, decoder: &dec)
            let cleaned = text != nil && removeFillers ? TextCleaner.stripFillers(text!) : (text ?? "")
            await MainActor.run {
                self.streamDecoder = dec
                if !cleaned.isEmpty {
                    self.streamingText += (self.streamingText.isEmpty ? "" : " ") + cleaned
                    self.streamingWords = self.streamingText.split(separator: " ").count
                    // Type directly (no clipboard); keep a space between slices.
                    let needsSpace = !self.streamingText.isEmpty && self.streamingText.last != " "
                    if needsSpace { Typer.type(" ") }
                    Typer.type(cleaned)
                }
                self.sliceInFlight = false
            }
        }
    }

    /// Finds a safe cut point near the end of the new audio: the middle of the
    /// quietest ~120 ms window in the trailing region. Falls back to the end.
    static func silenceCut(in samples: [Float], from start: Int) -> Int {
        let end = samples.count
        let window = 1_920  // 120 ms @ 16 kHz
        let searchBack = min(24_000, end - start)  // up to 1.5 s back
        let floor = max(start + 16_000, end - searchBack)
        var bestIdx = end
        var bestRMS: Float = .greatestFiniteMagnitude
        var i = end - window
        while i >= floor {
            let seg = samples[i..<(i + window)]
            var acc: Float = 0
            for s in seg { acc += s * s }
            let rms = sqrt(acc / Float(window))
            if rms < bestRMS {
                bestRMS = rms
                bestIdx = i + window / 2
                if rms < 0.004 { break }  // quiet enough — stop early
            }
            i -= 960  // 60 ms steps
        }
        return min(bestIdx, end)
    }

    // MARK: - Dictation flow (hold & speak)

    private func beginDictation() {
        keyIsDown = true
        guard !isRecording else { return }
        guard !isStreaming else { return }         // streaming owns the mic
        guard !notes.isRunning else { return }   // note session owns the mic
        guard transcriber.isReady else { return }  // model not loaded yet
        do {
            try recorder.start()
            recordStart = Date()
            isRecording = true
            overlay.show(listening: true,
                         key: KeyNames.name(forCode: store.settings.hotkeyKeyCode))
        } catch {
            lastError = "Mic error: \(error.localizedDescription)"
        }
    }

    private func endDictation() {
        keyIsDown = false
        guard isRecording else { return }
        isRecording = false
        overlay.show(listening: false)  // switch to "Transcribing…"
        let duration = Date().timeIntervalSince(recordStart)
        let samples = recorder.stop()

        guard duration >= 0.4, samples.count > 1600 else {
            overlay.hide()  // too short — treat as accidental tap
            return
        }

        transcriptionTask?.cancel()
        transcriptionTask = Task { [weak self] in
            guard let self else { return }
            let raw = await self.transcriber.transcribe(samples)
            guard !Task.isCancelled else { return }
            guard let raw else {
                self.lastError = "Transcription failed"
                self.overlay.hide()
                return
            }
            // Clean: strip the leading-dot artifact (key-click transient) and,
            // if enabled, filler words. An all-artifact transcript ("." only)
            // is discarded entirely instead of pasting a lone dot.
            let text = TextCleaner.clean(raw, removeFillers: self.store.settings.removeFillers)
            guard !text.isEmpty else {
                self.overlay.hide()
                return
            }
            self.lastText = text
            let frontApp = NSWorkspace.shared.frontmostApplication?.localizedName
            self.store.add(text: text, duration: duration, app: frontApp)
            Paster.paste(text)
            self.overlay.hide()
        }
    }
}
