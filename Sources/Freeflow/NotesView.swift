import SwiftUI
import AVFoundation

/// Live note-taking session: streaming VAD splits speech at natural pauses,
/// each pause starts a new line, text appears as it's transcribed.
struct NotesView: View {
    @ObservedObject var engine: NoteEngine
    var onStop: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(spacing: 10) {
                if engine.isSpeaking {
                    Circle().fill(.red).frame(width: 9, height: 9)
                        .transition(.opacity)
                } else {
                    Circle().stroke(.red, lineWidth: 1.5).frame(width: 9, height: 9)
                }
                Text(engine.isRunning ? "Recording notes" : "Session ended")
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
                Text(timeString(engine.elapsed))
                    .font(.system(size: 13).monospacedDigit())
                    .foregroundStyle(.secondary)
                Text("\(engine.lines.count) lines")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .animation(.easeOut(duration: 0.15), value: engine.isSpeaking)

            Divider()

            // Live notes
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        if engine.lines.isEmpty {
                            Text("Start talking — each pause starts a new line.\nTranscribed live, entirely on your Mac.")
                                .font(.system(size: 13))
                                .foregroundStyle(.secondary)
                                .padding(.top, 24)
                                .frame(maxWidth: .infinity)
                        }
                        ForEach(engine.lines) { line in
                            HStack(alignment: .firstTextBaseline, spacing: 10) {
                                Text("+" + timeString(line.offsetSeconds))
                                    .font(.system(size: 10).monospacedDigit())
                                    .foregroundStyle(.tertiary)
                                    .frame(width: 44, alignment: .leading)
                                Text(line.text)
                                    .font(.system(size: 13))
                                    .textSelection(.enabled)
                            }
                            .id(line.id)
                        }
                        if engine.isSpeaking {
                            HStack(spacing: 6) {
                                Circle().fill(.red).frame(width: 5, height: 5)
                                Text("listening…")
                                    .font(.system(size: 11)).foregroundStyle(.tertiary)
                            }
                        }
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .onChange(of: engine.lines.count) { _, _ in
                    if let last = engine.lines.last {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
            .frame(maxHeight: .infinity, alignment: .top)

            Divider()

            // Footer
            HStack {
                if engine.isRunning {
                    Button {
                        let text = engine.stop()
                        save(text)
                    } label: {
                        Label("Stop & Save", systemImage: "stop.fill")
                            .font(.system(size: 13, weight: .semibold))
                            .padding(.horizontal, 16).padding(.vertical, 8)
                            .background(RoundedRectangle(cornerRadius: 8).fill(Brand.accent))
                            .foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)
                } else {
                    Label("Saved to history", systemImage: "checkmark.circle.fill")
                        .font(.system(size: 12)).foregroundStyle(.green)
                }
                Spacer()
            }
            .padding(14)
        }
        .frame(minWidth: 520, minHeight: 420)
        .background(Brand.sageBG)
    }

    private func save(_ text: String) {
        onStop()
    }

    private func timeString(_ t: TimeInterval) -> String {
        let m = Int(t) / 60, s = Int(t) % 60
        return String(format: "%d:%02d", m, s)
    }
}
