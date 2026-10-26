import Foundation
import AppKit
import CoreGraphics

/// Types text at the current cursor location by placing it on the clipboard,
/// synthesizing Cmd+V, then restoring the previous clipboard contents.
enum Paster {
    static func paste(_ text: String) {
        guard !text.isEmpty else { return }
        let pasteboard = NSPasteboard.general

        // Remember everything currently on the clipboard (all types)
        let savedItems = pasteboard.pasteboardItems?.compactMap { item -> NSPasteboardItem? in
            let copy = NSPasteboardItem()
            for type in item.types where type.rawValue != "org.nspasteboard.ConcealedType" {
                if let data = item.data(forType: type) {
                    copy.setData(data, forType: type)
                }
            }
            return copy
        } ?? []

        // Give the user's clipboard back if paste fails or app quits mid-paste
        var cleared = false
        defer {
            if !cleared, !savedItems.isEmpty {
                pasteboard.clearContents()
                pasteboard.writeObjects(savedItems)
            }
        }

        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        // Small delay so the frontmost app sees the new clipboard
        usleep(120_000)

        // Cmd+V to whatever currently has focus
        let src = CGEventSource(stateID: .combinedSessionState)
        let vKey: CGKeyCode = 9
        let down = CGEvent(keyboardEventSource: src, virtualKey: vKey, keyDown: true)
        let up = CGEvent(keyboardEventSource: src, virtualKey: vKey, keyDown: false)
        down?.flags = .maskCommand
        up?.flags = .maskCommand
        down?.post(tap: .cgAnnotatedSessionEventTap)
        usleep(60_000)
        up?.post(tap: .cgAnnotatedSessionEventTap)

        // Let the target app process the paste before restoring the clipboard
        usleep(600_000)
        cleared = true

        if !savedItems.isEmpty {
            pasteboard.clearContents()
            pasteboard.writeObjects(savedItems)
        }
    }
}
