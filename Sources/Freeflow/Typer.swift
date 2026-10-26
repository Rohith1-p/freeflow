import Foundation
import CoreGraphics

/// Types text directly at the cursor via CGEvent unicode keyboard events.
/// Used for live streaming: no clipboard round-trips, no races, instant.
enum Typer {
    /// CGEvent carries at most ~20 UTF-16 units per event.
    private static let maxChunk = 20

    static func type(_ text: String) {
        guard !text.isEmpty else { return }
        let src = CGEventSource(stateID: .combinedSessionState)
        for chunk in chunks(of: text) {
            let utf16 = Array(chunk.utf16)
            guard let down = CGEvent(keyboardEventSource: src, virtualKey: 0, keyDown: true) else { continue }
            utf16.withUnsafeBufferPointer { buf in
                down.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: buf.baseAddress)
            }
            down.post(tap: .cgAnnotatedSessionEventTap)
        }
    }

    private static func chunks(of text: String) -> [String] {
        var out: [String] = []
        var current = ""
        for ch in text {
            current.append(ch)
            if current.count >= maxChunk {
                out.append(current)
                current = ""
            }
        }
        if !current.isEmpty { out.append(current) }
        return out
    }
}
