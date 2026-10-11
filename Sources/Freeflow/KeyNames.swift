import Foundation

/// Friendly names for dictation key codes, shared across the app.
enum KeyNames {
    static let table: [UInt64: String] = [
        59: "⌃ Control", 61: "⌃ Control", 63: "fn",
        58: "⌥ Option", 56: "⇧ Shift", 55: "⌘ Command",
        49: "Space", 57: "⇪ Caps Lock",
    ]

    static func name(forCode code: UInt64) -> String {
        table[code] ?? "Key \(code)"
    }
}
