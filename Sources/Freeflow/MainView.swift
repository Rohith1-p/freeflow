import SwiftUI
import Combine

/// Shared UI routing so the menu bar can drive in-window navigation.
@MainActor
final class UIRouter: ObservableObject {
    static let shared = UIRouter()
    enum Page: String { case dictation, settings }
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

/// Main experience: inset rounded sidebar (Dictation / Settings) + content.
struct MainView: View {
    @ObservedObject var state: AppState
    @ObservedObject private var router = UIRouter.shared
    @ObservedObject private var store = Store.shared
    @State private var copiedEntry: DictationEntry?
    @Namespace private var sidebarAnimation

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
        HStack(spacing: 16) {
            sidebar
            content
        }
        .padding(12)
        .frame(minWidth: 700, minHeight: 480)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - Sidebar (inset rounded panel)

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                AppIconMark(size: 30)
                Text("Freeflow")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
            }
            .padding(.horizontal, 10)
            .padding(.top, 6)
            .padding(.bottom, 14)

            navItem(page: .dictation, icon: "mic.fill", title: "Dictation",
                    badge: state.isRecording ? "●" : nil)
            navItem(page: .settings, icon: "gearshape", title: "Settings", badge: nil)

            Spacer()

            Label("All local · nothing leaves your Mac", systemImage: "lock.shield")
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 10)
                .padding(.bottom, 6)
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

    private func navItem(page: UIRouter.Page, icon: String, title: String, badge: String?) -> some View {        let selected = router.page == page
        return HStack(spacing: 9) {
            ZStack {
                // Sliding selection pill (animates between items)
                if selected {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Brand.blue)
                        .matchedGeometryEffect(id: "SidebarSelection", in: sidebarAnimation)
                        .shadow(color: Brand.blue.opacity(0.3), radius: 8, x: 0, y: 4)
                }
                Image(systemName: icon)
                    .font(.system(size: 12, weight: selected ? .semibold : .regular))
                    .foregroundStyle(selected ? .white : .secondary)
                    .scaleEffect(selected ? 1.1 : 1.0)
            }
            .frame(width: 24, height: 24)

            Text(title)
                .font(.system(size: 13, weight: selected ? .semibold : .regular))
                .foregroundStyle(selected ? Brand.blue : .primary)
            Spacer()
            if let badge {
                Text(badge).font(.system(size: 11, weight: .bold)).foregroundStyle(.red)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                router.page = page
            }
        }
    }

    // MARK: - Content switching

    @ViewBuilder
    private var content: some View {
        switch router.page {
        case .dictation: dictationPage
        case .settings: SettingsView(state: state)
        }
    }

    // MARK: - Dictation page

    private var dictationPage: some View {
        VStack(spacing: 0) {
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
            .padding(.horizontal, 6)
            .padding(.top, 8)
            .padding(.bottom, 14)

            if store.todaysEntries.isEmpty {
                emptyState
            } else {
                historyList
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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
        .card(cornerRadius: 14)
    }

    private func copy(_ entry: DictationEntry) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(entry.text, forType: .string)
        copiedEntry = entry
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            if copiedEntry?.id == entry.id { copiedEntry = nil }
        }
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
                    Label(entry.app ?? "Unknown app", systemImage: "app")
                        .font(.system(size: 9)).foregroundStyle(.tertiary)
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
