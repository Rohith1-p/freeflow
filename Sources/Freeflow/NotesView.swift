import SwiftUI
import AVFoundation

/// Live note-taking session: streaming VAD splits speech at natural pauses,
/// each pause starts a new line, text appears as it's transcribed.
struct NotesView: View {
    @ObservedObject var engine: NoteEngine
    var embedded = false
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
                        onStop()
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

    private func timeString(_ t: TimeInterval) -> String {
        let m = Int(t) / 60, s = Int(t) % 60
        return String(format: "%d:%02d", m, s)
    }
}

/// Saved note sessions: date-grouped cards with full text, copy, delete.
struct NotesListView: View {
    @ObservedObject var state: AppState
    @ObservedObject private var store = Store.shared
    @State private var copiedID: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Text("Notes")
                    .font(.system(size: 17, weight: .bold))
                Spacer()
                if !store.noteSessions.isEmpty {
                    Text("\(store.noteSessions.count) sessions")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }
                startButton
            }
            .padding(.top, 6)

            if state.notes.isRunning {
                NotesView(engine: state.notes, embedded: true) {
                    NotificationCenter.default.post(name: .init("FreeflowToggleNotes"), object: nil)
                }
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color(nsColor: .controlBackgroundColor)))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Brand.accent.opacity(0.35), lineWidth: 1))
            }

            if store.noteSessions.isEmpty {
                VStack(spacing: 12) {
                    ZStack {
                        Circle().fill(Brand.accentSoft).frame(width: 64, height: 64)
                        Image(systemName: "note.text")
                            .font(.system(size: 24))
                            .foregroundStyle(Brand.accent)
                    }
                    Text("No notes yet")
                        .font(.system(size: 15, weight: .semibold))
                    Text("Each pause starts a new line, transcribed live.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        ForEach(store.groupedNotes, id: \.id) { group in
                            Text(group.label.uppercased())
                                .font(.system(size: 10.5, weight: .semibold))
                                .foregroundStyle(.secondary)
                                .padding(.leading, 4)
                            VStack(spacing: 0) {
                                ForEach(Array(group.sessions.enumerated()), id: \.element.id) { idx, session in
                                    noteRow(session)
                                    if idx < group.sessions.count - 1 {
                                        Divider().opacity(0.5)
                                    }
                                }
                            }
                            .padding(.vertical, 6)
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(Color(nsColor: .controlBackgroundColor)))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1))
                        }
                    }
                    .padding(.bottom, 12)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.leading, 6)
    }

    @ViewBuilder
    private var startButton: some View {
        if state.notes.isRunning {
            Button {
                NotificationCenter.default.post(name: .init("FreeflowShowNotes"), object: nil)
            } label: {
                Label("View live notes", systemImage: "waveform")
                    .font(.system(size: 12, weight: .semibold))
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(RoundedRectangle(cornerRadius: 7).fill(Brand.accentSoft))
                    .foregroundStyle(Brand.accent)
            }
            .buttonStyle(.plain)
        } else {
            Button {
                NotificationCenter.default.post(name: .init("FreeflowToggleNotes"), object: nil)
            } label: {
                Label("Start note session", systemImage: "record.circle")
                    .font(.system(size: 12, weight: .semibold))
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(RoundedRectangle(cornerRadius: 7).fill(Brand.accent))
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
        }
    }

    private func noteRow(_ session: NoteSession) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Text(session.startedAt.formatted(date: .omitted, time: .shortened))
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(.secondary)
                Text("\(timeString(session.durationSeconds)) · \(session.lines.count) lines · \(session.wordCount) words")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                Spacer()
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(session.fullText, forType: .string)
                    copiedID = session.id
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                        if copiedID == session.id { copiedID = nil }
                    }
                } label: {
                    Image(systemName: copiedID == session.id ? "checkmark" : "doc.on.doc")
                        .foregroundStyle(copiedID == session.id ? .green : .secondary)
                }
                .buttonStyle(.borderless)
                .help("Copy note")
                Button {
                    store.deleteNote(session.id)
                } label: {
                    Image(systemName: "trash").foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .help("Delete note")
            }
            VStack(alignment: .leading, spacing: 4) {
                ForEach(session.lines) { line in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text("+" + timeString(line.offsetSeconds))
                            .font(.system(size: 10).monospacedDigit())
                            .foregroundStyle(.tertiary)
                            .frame(width: 44, alignment: .leading)
                        Text(line.text)
                            .font(.system(size: 13))
                            .textSelection(.enabled)
                    }
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private func timeString(_ t: TimeInterval) -> String {
        let m = Int(t) / 60, s = Int(t) % 60
        return String(format: "%d:%02d", m, s)
    }
}
