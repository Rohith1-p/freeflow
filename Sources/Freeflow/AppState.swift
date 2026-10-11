import Foundation
import AppKit
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
    private let recorder = AudioRecorder()
    private let hotkey = HotkeyMonitor()
    private var recordStart = Date()
    private var transcriptionTask: Task<Void, Never>?

    func startEngine() {
        hotkey.onKeyDown = { [weak self] in self?.beginDictation() }
        hotkey.onKeyUp = { [weak self] in self?.endDictation() }
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

    // MARK: - Dictation flow

    private func beginDictation() {
        keyIsDown = true
        guard !isRecording else { return }
        guard transcriber.isReady else { return }  // model not loaded yet
        do {
            try recorder.start()
            recordStart = Date()
            isRecording = true
            overlay.show(listening: true)
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
            let text = await self.transcriber.transcribe(samples)
            guard !Task.isCancelled else { return }
            guard let text else {
                self.lastError = "Transcription failed"
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
