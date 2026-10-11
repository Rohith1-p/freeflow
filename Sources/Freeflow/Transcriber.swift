import Foundation
import FluidAudio

/// Wraps FluidAudio Parakeet ASR: model download with progress + transcription.
@MainActor
final class Transcriber: ObservableObject {
    enum State: Equatable {
        case idle
        case downloading(Double)   // 0...1
        case compiling(String)    // CoreML compile phase
        case loading
        case ready
        case failed(String)
    }

    @Published private(set) var state: State = .idle

    private var manager: AsrManager?
    private var models: AsrModels?
    private var decoderState: TdtDecoderState?

    /// Downloads models if needed (reports progress), then loads them.
    func prepare() async {
        if manager != nil { return }
        state = .loading
        do {
            let models = try await AsrModels.downloadAndLoad(version: .v3) { [weak self] progress in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    switch progress.phase {
                    case .listing:
                        self.state = .downloading(0.01)
                    case .downloading:
                        // Never let the bar go backwards or stall at zero
                        let f = max(0.02, progress.fractionCompleted)
                        if case .downloading(let cur) = self.state {
                            self.state = .downloading(max(cur, f))
                        } else {
                            self.state = .downloading(f)
                        }
                    case .compiling(let model):
                        self.state = .compiling(model)
                    }
                }
            }
            self.models = models
            state = .compiling("Core ML")
            let asr = AsrManager(config: .default)
            try await asr.loadModels(models)
            decoderState = try TdtDecoderState()
            manager = asr
            state = .ready
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    /// Transcribes 16 kHz mono samples. Returns nil on error.
    func transcribe(_ samples: [Float]) async -> String? {
        guard let manager, var decState = decoderState else { return nil }
        do {
            let result = try await manager.transcribe(samples, decoderState: &decState)
            decoderState = decState
            let text = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty ? nil : text
        } catch {
            FileHandle.standardError.write(Data("transcribe error: \(error)\n".utf8))
            return nil
        }
    }

    var isReady: Bool { state == .ready }
}
