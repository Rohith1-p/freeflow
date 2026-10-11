import SwiftUI

/// Switches between onboarding and the main experience.
struct RootView: View {
    @ObservedObject var state: AppState
    var onOpenSettings: () -> Void

    @ObservedObject private var store = Store.shared

    var body: some View {
        if store.settings.completedOnboarding {
            MainView(state: state, onOpenSettings: onOpenSettings)
        } else {
            OnboardingView(state: state)
        }
    }
}

/// WisprFlow-style home: sidebar, greeting, history, stats.
struct MainView: View {
    @ObservedObject var state: AppState
    var onOpenSettings: () -> Void

    @ObservedObject private var store = Store.shared
    @State private var copiedEntry: DictationEntry?

    private var greeting: String {
        let h = Calendar.current.component(.hour, from: Date())
        switch h {
        case 5..<12: return "Good morning"
        case 12..<17: return "Good afternoon"
        default: return "Good evening"
        }
    }

    private var hotkeyName: String {
        KeyNames.name(forCode: store.settings.hotkeyKeyCode)
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider()
            VStack(spacing: 0) {
                header
                Divider()
                if store.todaysEntries.isEmpty { emptyState } else { historyList }
            }
            Divider()
            statsPanel
        }
        .frame(minWidth: 680, minHeight: 460)
        .background(.ultraThinMaterial)
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                ZStack {
                    Circle().fill(Brand.inkDark).frame(width: 32, height: 32)
                    Text("🎙").font(.system(size: 15))
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text("Freeflow").font(.system(size: 14, weight: .bold, design: .rounded))
                    Text("Local dictation").font(.system(size: 10)).foregroundStyle(.secondary)
                }
            }
            .padding(14)

            navRow(icon: "mic.fill", title: "Dictation", selected: true, badge: state.isRecording ? "●" : nil)
                .onTapGesture {}

            Spacer()

            navRow(icon: "gearshape", title: "Settings", selected: false, badge: nil)
                .onTapGesture { onOpenSettings() }

            Label("All local · nothing leaves your Mac", systemImage: "lock.shield")
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)
                .padding(12)
        }
        .frame(width: 172)
    }

    private func navRow(icon: String, title: String, selected: Bool, badge: String?) -> some View {
        HStack(spacing: 9) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundStyle(selected ? Brand.blue : .secondary)
                .frame(width: 16)
            Text(title)
                .font(.system(size: 13, weight: selected ? .semibold : .regular))
                .foregroundStyle(selected ? Brand.ink : .secondary)
            Spacer()
            if let badge {
                Text(badge).font(.system(size: 12, weight: .bold)).foregroundStyle(.red)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background {
            if selected { RoundedRectangle(cornerRadius: 8).fill(Brand.blueSoft) }
        }
        .contentShape(Rectangle())
        .padding(.horizontal, 8)
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text("\(greeting), get into the flow")
                    .font(.system(size: 21, weight: .bold, design: .rounded))
                Spacer()
                statusPill
            }
            Text("Hold \(hotkeyName) and speak — your words land at your cursor.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }

    @ViewBuilder
    private var statusPill: some View {
        if state.isRecording {
            HStack(spacing: 6) {
                Circle().fill(.red).frame(width: 8, height: 8)
                Text("Recording…").font(.system(size: 12, weight: .semibold))
            }
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(Capsule().fill(Color.red.opacity(0.1)))
            .foregroundStyle(.red)
        } else if state.transcriber.isReady {
            Label("Ready", systemImage: "checkmark.circle.fill")
                .font(.system(size: 12))
                .foregroundStyle(.green)
        } else {
            Label("Loading model…", systemImage: "arrow.down.circle")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - History

    private var emptyState: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle().fill(Brand.blueSoft).frame(width: 64, height: 64)
                Image(systemName: "mic.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(Brand.blue)
            }
            Text("No dictations yet today")
                .font(.system(size: 15, weight: .semibold))
            Text("Hold \(hotkeyName), speak, release — text lands at your cursor.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var historyList: some View {
        List {
            Section("Today") {
                ForEach(store.todaysEntries) { entry in
                    EntryRow(entry: entry,
                             copied: copiedEntry?.id == entry.id,
                             onCopy: { copy(entry) },
                             onDelete: { store.delete(entry) })
                }
            }
        }
        .listStyle(.inset)
    }

    private func copy(_ entry: DictationEntry) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(entry.text, forType: .string)
        copiedEntry = entry
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            if copiedEntry?.id == entry.id { copiedEntry = nil }
        }
    }

    // MARK: - Stats

    private var statsPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Your stats").font(.system(size: 14, weight: .bold))
            statCard(title: "Total words", value: "\(store.totalWords)")
            statCard(title: "Dictations today", value: "\(store.todaysEntries.count)")
            statCard(title: "All time", value: "\(store.entries.count)")
            Spacer()
            if let last = store.entries.first, !last.text.isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    Text("LAST DICTATION").font(.system(size: 9, weight: .bold)).foregroundStyle(.tertiary)
                    Text(last.text)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(4)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .glassCard(cornerRadius: 9)
            }
        }
        .padding(14)
        .frame(width: 186)
    }

    private func statCard(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value)
                .font(.system(size: 20, weight: .bold, design: .rounded))
            Text(title).font(.system(size: 10)).foregroundStyle(.secondary)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(cornerRadius: 9)
    }
}

struct EntryRow: View {
    let entry: DictationEntry
    let copied: Bool
    let onCopy: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text(entry.timestamp.formatted(date: .omitted, time: .shortened))
                .font(.system(size: 11).monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 52, alignment: .leading)
            VStack(alignment: .leading, spacing: 3) {
                Text(entry.text)
                    .font(.system(size: 13))
                    .textSelection(.enabled)
                HStack(spacing: 10) {
                    if entry.app != nil || true {
                        Label(entry.app ?? "Unknown app", systemImage: "app")
                            .font(.system(size: 9)).foregroundStyle(.tertiary)
                    }
                    if entry.wordCount > 0 {
                        Text("\(entry.wordCount) words").font(.system(size: 9)).foregroundStyle(.tertiary)
                    }
                }
            }
            Spacer()
            HStack(spacing: 8) {
                Button { onCopy() } label: {
                    Image(systemName: copied ? "checkmark" : "doc.on.doc")
                        .foregroundStyle(copied ? .green : .secondary)
                }
                .buttonStyle(.borderless)
                .help("Copy")
                Button(action: onDelete) {
                    Image(systemName: "trash").foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .help("Delete")
            }
        }
        .padding(.vertical, 3)
    }
}
