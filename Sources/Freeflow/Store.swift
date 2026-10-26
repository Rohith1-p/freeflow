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
enum InputMode: String, CaseIterable, Identifiable, Codable {
    case holdAndSpeak
    case freeflowSpeech
    var id: String { rawValue }
    var label: String {
        switch self {
        case .holdAndSpeak: return "Hold & speak"
        case .freeflowSpeech: return "Freeflow speech"
        }
    }
    var caption: String {
        switch self {
        case .holdAndSpeak: return "Hold the key while talking. Release to paste."
        case .freeflowSpeech: return "Double-tap the key to start. Words flow live. Double-tap again to stop."
        }
    }
}

struct Settings: Codable, Equatable {
    var hotkeyKeyCode: UInt64 = 59          // left control
    var completedOnboarding = false
    var showInHistory = true
    var launchAtLogin = true
    var theme: String = "system"            // system | light | dark
    var userName: String = ""               // for the greeting
    var inputMode: InputMode = .holdAndSpeak
    var removeFillers = true                // strip "uh", "um" from transcripts

    enum CodingKeys: String, CodingKey {
        case hotkeyKeyCode, completedOnboarding, showInHistory, launchAtLogin
        case theme, userName, inputMode, removeFillers
    }

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        hotkeyKeyCode = try c.decodeIfPresent(UInt64.self, forKey: .hotkeyKeyCode) ?? 59
        completedOnboarding = try c.decodeIfPresent(Bool.self, forKey: .completedOnboarding) ?? false
        showInHistory = try c.decodeIfPresent(Bool.self, forKey: .showInHistory) ?? true
        launchAtLogin = try c.decodeIfPresent(Bool.self, forKey: .launchAtLogin) ?? true
        theme = try c.decodeIfPresent(String.self, forKey: .theme) ?? "system"
        userName = try c.decodeIfPresent(String.self, forKey: .userName) ?? ""
        inputMode = InputMode(rawValue: try c.decodeIfPresent(String.self, forKey: .inputMode) ?? "") ?? .holdAndSpeak
        removeFillers = try c.decodeIfPresent(Bool.self, forKey: .removeFillers) ?? true
    }
}

/// JSON-backed storage for settings and dictation history.
/// All access is main-actor confined (UI-adjacent, tiny data).
@MainActor
final class Store: ObservableObject {
    @Published private(set) var entries: [DictationEntry] = []
    @Published var settings = Settings() { didSet { persistSettings() } }

    static let shared = Store()

    @Published private(set) var noteSessions: [NoteSession] = []
    private let notesURL: URL

    private let dir: URL
    private let settingsURL: URL
    private let historyURL: URL

    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        dir = base.appendingPathComponent("Freeflow", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        settingsURL = dir.appendingPathComponent("settings.json")
        historyURL = dir.appendingPathComponent("history.json")
        notesURL = dir.appendingPathComponent("notes.json")
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

    var wordsToday: Int {
        todaysEntries.reduce(0) { $0 + $1.wordCount }
    }

    /// Words per minute across today's dictations.
    var wpmToday: Int {
        let secs = todaysEntries.reduce(0) { $0 + $1.durationSeconds }
        let words = todaysEntries.reduce(0) { $0 + $1.wordCount }
        guard secs > 0.5 else { return 0 }
        return Int(Double(words) / (secs / 60))
    }

    /// Consecutive days (ending today or yesterday) with at least one dictation.
    var streakDays: Int {
        let cal = Calendar.current
        var day = cal.startOfDay(for: Date())
        if !entries.contains(where: { cal.isDate($0.timestamp, inSameDayAs: day) }) {
            day = cal.date(byAdding: .day, value: -1, to: day)!
        }
        var streak = 0
        while entries.contains(where: { cal.isDate($0.timestamp, inSameDayAs: day) }) {
            streak += 1
            day = cal.date(byAdding: .day, value: -1, to: day)!
        }
        return streak
    }

    /// Notes grouped by day, newest first.
    var groupedNotes: [(id: Date, label: String, sessions: [NoteSession])] {
        let cal = Calendar.current
        let dict = Dictionary(grouping: noteSessions) { cal.startOfDay(for: $0.startedAt) }
        return dict.keys.sorted(by: >).map { day in
            let label: String
            if cal.isDateInToday(day) { label = "Today" }
            else if cal.isDateInYesterday(day) { label = "Yesterday" }
            else { label = day.formatted(date: .long, time: .omitted) }
            return (day, label, dict[day]!.sorted { $0.startedAt > $1.startedAt })
        }
    }

    /// History grouped by day, newest first. Labels: Today / Yesterday / date.
    var groupedEntries: [(id: Date, label: String, entries: [DictationEntry])] {
        let cal = Calendar.current
        let dict = Dictionary(grouping: entries) { cal.startOfDay(for: $0.timestamp) }
        return dict.keys.sorted(by: >).map { day in
            let label: String
            if cal.isDateInToday(day) { label = "Today" }
            else if cal.isDateInYesterday(day) { label = "Yesterday" }
            else { label = day.formatted(date: .long, time: .omitted) }
            return (day, label, dict[day]!.sorted { $0.timestamp > $1.timestamp })
        }
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
        if let data = try? Data(contentsOf: notesURL),
           let n = try? JSONDecoder().decode([NoteSession].self, from: data) {
            noteSessions = n
        }
    }

    // MARK: Notes

    func addNote(_ session: NoteSession) {
        noteSessions.insert(session, at: 0)
        if noteSessions.count > 500 { noteSessions.removeLast(noteSessions.count - 500) }
        persistNotes()
    }

    func deleteNote(_ id: UUID) {
        noteSessions.removeAll { $0.id == id }
        persistNotes()
    }

    private func persistNotes() {
        if let data = try? JSONEncoder().encode(noteSessions) {
            try? data.write(to: notesURL, options: .atomic)
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
