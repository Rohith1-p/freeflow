import Foundation

/// One completed dictation.
struct DictationEntry: Identifiable, Codable, Equatable {
    let id: UUID
    let timestamp: Date
    let text: String
    let durationSeconds: Double
    let app: String?          // frontmost app name when pasted (best effort)

    var wordCount: Int { text.split(whereSeparator: \.isWhitespace).count }
    var wpm: Int {
        guard durationSeconds > 0.5 else { return 0 }
        return Int(Double(wordCount) / (durationSeconds / 60))
    }
}

/// App settings, persisted as JSON.
struct Settings: Codable, Equatable {
    var hotkeyKeyCode: UInt64 = 59          // left control
    var completedOnboarding = false
    var showInHistory = true
    var launchAtLogin = true
    var theme: String = "system"            // system | light | dark
}

/// JSON-backed storage for settings and dictation history.
/// All access is main-actor confined (UI-adjacent, tiny data).
@MainActor
final class Store: ObservableObject {
    @Published private(set) var entries: [DictationEntry] = []
    @Published var settings = Settings() { didSet { persistSettings() } }

    static let shared = Store()

    private let dir: URL
    private let settingsURL: URL
    private let historyURL: URL

    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        dir = base.appendingPathComponent("Freeflow", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        settingsURL = dir.appendingPathComponent("settings.json")
        historyURL = dir.appendingPathComponent("history.json")
        load()
    }

    func add(text: String, duration: Double, app: String?) {
        guard settings.showInHistory, !text.isEmpty else { return }
        let entry = DictationEntry(
            id: UUID(), timestamp: Date(), text: text,
            durationSeconds: duration, app: app
        )
        entries.insert(entry, at: 0)
        // Cap history to keep the JSON light
        if entries.count > 2000 { entries.removeLast(entries.count - 2000) }
        persistHistory()
    }

    func delete(_ entry: DictationEntry) {
        entries.removeAll { $0.id == entry.id }
        persistHistory()
    }

    var todaysEntries: [DictationEntry] {
        let cal = Calendar.current
        return entries.filter { cal.isDateInToday($0.timestamp) }
    }

    var totalWords: Int { entries.reduce(0) { $0 + $1.wordCount } }

    // MARK: - Persistence

    private func load() {
        if let data = try? Data(contentsOf: settingsURL),
           let s = try? JSONDecoder().decode(Settings.self, from: data) {
            settings = s
        }
        if let data = try? Data(contentsOf: historyURL),
           let e = try? JSONDecoder().decode([DictationEntry].self, from: data) {
            entries = e
        }
    }

    private func persistSettings() {
        if let data = try? JSONEncoder().encode(settings) {
            try? data.write(to: settingsURL, options: .atomic)
        }
    }

    private func persistHistory() {
        if let data = try? JSONEncoder().encode(entries) {
            try? data.write(to: historyURL, options: .atomic)
        }
    }
}
