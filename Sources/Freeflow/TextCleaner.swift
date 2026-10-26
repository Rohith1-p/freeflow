import Foundation

/// Transcript cleanup: filler-word removal + leading punctuation artifacts.
enum TextCleaner {
    private static let fillers: Set<String> = [
        "uh", "uhh", "uhhh", "um", "umm", "ummm", "erm", "hmm", "hmmm", "huh",
    ]

    /// Removes standalone filler words ("uh", "um", …) — never inside words.
    static func stripFillers(_ text: String) -> String {
        let words = text
            .split(separator: " ", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: ".,!?;:\"'()")) }
        let kept = words.filter { word in
            guard !word.isEmpty else { return true }
            return !fillers.contains(word.lowercased())
        }
        var out = kept.joined(separator: " ")
        out = stripLeadingPunctuation(out)
        return out
    }

    /// Strips stray leading punctuation artifacts (e.g. the lone "." some
    /// models emit from the key-press transient).
    static func stripLeadingPunctuation(_ text: String) -> String {
        var out = text.trimmingCharacters(in: .whitespacesAndNewlines)
        while let first = out.first, first == "." || first == "," {
            out = String(out.dropFirst()).trimmingCharacters(in: .whitespaces)
        }
        return out
    }

    /// Full cleanup pass for a finished transcript.
    static func clean(_ text: String, removeFillers: Bool) -> String {
        var out = stripLeadingPunctuation(text)
        if removeFillers { out = stripFillers(out) }
        return out.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
