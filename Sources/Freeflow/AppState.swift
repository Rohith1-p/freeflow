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
    }

    func restartHotkey() {
        hotkey.start(keyCodes: [store.settings.hotkeyKeyCode])
    }

    var hotkeyActive: Bool { hotkey.isActive }

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
