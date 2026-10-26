import SwiftUI
import Combine

/// Shared UI routing so the menu bar can drive in-window navigation.
@MainActor
final class UIRouter: ObservableObject {
    static let shared = UIRouter()
    enum Page { case dictation, notes, settings }
    @Published var page: Page = .dictation
}

/// Switches between onboarding and the main experience.
struct RootView: View {
    @ObservedObject var state: AppState

    @ObservedObject private var store = Store.shared

    var body: some View {
        if store.settings.completedOnboarding {
            MainView(state: state)
        } else {
            OnboardingView(state: state)
        }
    }
}

/// WisprFlow-style home: greeting with key badge, search, date-grouped
/// history cards, and a today-stats panel. Sidebar switches pages.
struct MainView: View {
    @ObservedObject var state: AppState
    @ObservedObject private var router = UIRouter.shared
    @ObservedObject private var store = Store.shared
    @State private var copiedEntry: DictationEntry?
    @Namespace private var sidebarAnimation
    @State private var search = ""

    private var greeting: String {
        let h = Calendar.current.component(.hour, from: Date())
        switch h {
        case 5..<12: return "Good morning"
        case 12..<17: return "Good afternoon"
        default: return "Good evening"
        }
    }

    private var firstName: String {
        let n = store.settings.userName.trimmingCharacters(in: .whitespaces)
        return n.isEmpty ? "there" : n.split(separator: " ").first.map(String.init) ?? "there"
    }

    private var hotkeyName: String {
        KeyNames.name(forCode: store.settings.hotkeyKeyCode)
    }

    var body: some View {
        HStack(spacing: 16) {
            sidebar
            switch router.page {
            case .dictation: dictationPage
            case .notes: NotesListView(state: state)
            case .settings: SettingsView(state: state)
            }
        }
        .padding(14)
        .frame(minWidth: 860, minHeight: 580)
        .background(Brand.sageBG)
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                AppIconMark(size: 30)
                Text("Freeflow")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
            }
            .padding(.horizontal, 10)
            .padding(.top, 4)
            .padding(.bottom, 14)

            navItem(icon: "mic.fill", title: "Dictation", page: .dictation,
                    badge: state.isRecording ? "●" : nil)
            navItem(icon: "note.text", title: "Notes", page: .notes,
                    badge: state.notes.isRunning ? "●" : nil)
            navItem(icon: "gearshape", title: "Settings", page: .settings, badge: nil)

            Spacer()

            VStack(alignment: .leading, spacing: 8) {
                if state.isRecording {
                    HStack(spacing: 6) {
                        Circle().fill(.red).frame(width: 7, height: 7)
                        Text("Recording…").font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundStyle(.red)
                }

                modelStatusRow

                Label("All local · nothing leaves your Mac", systemImage: "lock.shield")
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(8)
        .frame(width: 176)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.primary.opacity(0.035))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
        )
    }

    @ViewBuilder
    private var modelStatusRow: some View {
        HStack(spacing: 6) {
            switch state.transcriber.state {
            case .ready:
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.green)
                Text("Model ready").font(.system(size: 10.5, weight: .medium))
            case .downloading(let p):
                ProgressView(value: p).tint(Brand.accent).frame(width: 60)
                Text("\(Int(p * 100))%").font(.system(size: 10, weight: .semibold).monospacedDigit())
            case .compiling:
                ProgressView().controlSize(.mini)
                Text("Compiling…").font(.system(size: 10.5))
            case .failed(let msg):
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 11)).foregroundStyle(.orange)
                Text("Model failed").font(.system(size: 10.5, weight: .medium))
                    .help(msg)
            case .loading, .idle:
                ProgressView().controlSize(.mini)
                Text("Loading model…").font(.system(size: 10.5))
            }
        }
        .foregroundStyle(.secondary)
    }

    private func navItem(icon: String, title: String, page: UIRouter.Page, badge: String?) -> some View {
        let selected = router.page == page
        return HStack(spacing: 9) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundStyle(selected ? Brand.accent : .secondary)
                .frame(width: 16)
            Text(title)
                .font(.system(size: 13, weight: selected ? .semibold : .regular))
                .foregroundStyle(selected ? Brand.ink : .primary.opacity(0.75))
            Spacer()
            if let badge {
                Text(badge).font(.system(size: 12, weight: .bold)).foregroundStyle(.red)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background {
            if selected { RoundedRectangle(cornerRadius: 8).fill(Brand.accentSoft) }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                router.page = page
            }
        }
    }

    // MARK: - Dictation page

    private var dictationPage: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 16) {
                greetingAndHistory
                statsPanel
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var greetingAndHistory: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 8) {
                Text("\(firstName), start dictating with")
                    .font(.system(size: 17, weight: .bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                keyCap(hotkeyName)
                Spacer(minLength: 0)
            }
            .padding(.top, 6)

            searchBar

            if search.isEmpty && store.entries.isEmpty {
                emptyState
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                historyScroll
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func keyCap(_ label: String) -> some View {
        Text(label)
            .font(.system(size: 12, weight: .bold, design: .rounded))
            .foregroundStyle(Brand.accent)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(RoundedRectangle(cornerRadius: 6).fill(Brand.accentSoft))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Brand.accent.opacity(0.35), lineWidth: 1))
    }

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.tertiary)
                .font(.system(size: 12))
            TextField("Search dictations", text: $search)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
            if !search.isEmpty {
                Button {
                    search = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Brand.card)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }

    private var filteredEntries: [DictationEntry] {
        search.isEmpty
            ? store.entries
            : store.entries.filter { $0.text.localizedCaseInsensitiveContains(search) }
    }

    private var historyScroll: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                ForEach(store.groupedEntries, id: \.id) { group in
                    let dayEntries = group.entries.filter {
                        search.isEmpty || filteredEntries.contains($0)
                    }
                    if !dayEntries.isEmpty {
                        Text(group.label.uppercased())
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .padding(.leading, 4)
                        VStack(spacing: 0) {
                            ForEach(Array(dayEntries.enumerated()), id: \.element.id) { idx, entry in
                                EntryRow(entry: entry,
                                         copied: copiedEntry?.id == entry.id,
                                         onCopy: { copy(entry) },
                                         onDelete: { store.delete(entry) })
                                if idx < dayEntries.count - 1 {
                                    Divider().opacity(0.5)
                                }
                            }
                        }
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Brand.card)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
                        )
                    }
                }
            }
            .padding(.bottom, 12)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle().fill(Brand.accentSoft).frame(width: 64, height: 64)
                Image(systemName: "mic.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(Brand.accent)
            }
            Text("No dictations yet today")
                .font(.system(size: 15, weight: .semibold))
            Text("Hold \(hotkeyName), speak, release — text lands at your cursor.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func copy(_ entry: DictationEntry) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(entry.text, forType: .string)
        copiedEntry = entry
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            if copiedEntry?.id == entry.id { copiedEntry = nil }
        }
    }

    // MARK: - Stats panel

    private var statsPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            statBig(value: "\(store.wordsToday)", label: "total words today")
            statBig(value: "\(store.wpmToday)", label: "wpm today")
            statBig(value: "\(store.streakDays)",
                    label: store.streakDays == 1 ? "day streak" : "day streak 🔥")
            Divider().opacity(0.4)
            VStack(alignment: .leading, spacing: 4) {
                Text("All time").font(.system(size: 10, weight: .semibold)).foregroundStyle(.tertiary)
                Text("\(store.entries.count) dictations · \(store.totalWords) words")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(16)
        .frame(width: 170)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.primary.opacity(0.035))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
        )
    }

    private func statBig(value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(value)
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(Brand.ink)
                Text(label)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct EntryRow: View {
    let entry: DictationEntry
    let copied: Bool
    let onCopy: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(entry.timestamp.formatted(date: .omitted, time: .shortened))
                .font(.system(size: 11).monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 52, alignment: .leading)
                .padding(.top, 2)
            Text(entry.text)
                .font(.system(size: 13))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 10) {
                Button { onCopy() } label: {
                    Image(systemName: copied ? "checkmark" : "doc.on.doc")
                        .foregroundStyle(copied ? .green : .secondary)
                }
                .buttonStyle(.borderless)
                .help("Copy")
                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .help("Delete")
            }
            .opacity(0.85)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}
