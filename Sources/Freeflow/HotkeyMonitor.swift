import Foundation
import AppKit
import CoreGraphics

/// Push-to-talk hotkey via a listen-only CGEventTap.
///
/// Handles BOTH regular keys (keyDown/keyUp) and modifier-only keys
/// (Control, Option, Shift, Cmd, fn), which macOS reports as
/// `flagsChanged` events — never keyDown. Missing this means pressing
/// Control alone appears completely invisible to the app.
final class HotkeyMonitor {
    var onKeyDown: (() -> Void)?
    var onKeyUp: (() -> Void)?

    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var keyCodes: Set<UInt64> = [59]  // left control by default
    private var isDown = false

    /// keyCodes: CGKeyCode values (59 = left control, 61 = right control, 63 = fn)
    func start(keyCodes: Set<UInt64>) {
        self.keyCodes = keyCodes
        stop()

        let mask: CGEventMask =
            (1 << CGEventType.keyDown.rawValue)
            | (1 << CGEventType.keyUp.rawValue)
            | (1 << CGEventType.flagsChanged.rawValue)

        let callback: CGEventTapCallBack = { _, type, event, refcon in
            let monitor = Unmanaged<HotkeyMonitor>.fromOpaque(refcon!).takeUnretainedValue()
            monitor.handle(type: type, event: event)
            return Unmanaged.passUnretained(event)  // listen-only: pass through
        }

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            // Accessibility permission missing — onboarding surfaces this
            return
        }

        self.tap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        self.source = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    /// The CGEventFlag that corresponds to a modifier keycode, if it is one.
    private func flag(forCode code: UInt64) -> CGEventFlags? {
        switch code {
        case 59, 61: return .maskControl
        case 58: return .maskAlternate
        case 56: return .maskShift
        case 55: return .maskCommand
        case 63: return .maskSecondaryFn      // fn
        case 57: return .maskAlphaShift       // caps lock
        default: return nil
        }
    }

    private func handle(type: CGEventType, event: CGEvent) {
        let code = UInt64(event.getIntegerValueField(.keyboardEventKeycode))
        guard keyCodes.contains(code) else { return }

        switch type {
        case .flagsChanged:
            // Modifier key: pressed state = is its flag bit now set?
            guard let flag = flag(forCode: code) else { return }
            let pressed = event.flags.contains(flag)
            if pressed && !isDown {
                isDown = true
                onKeyDown?()
            } else if !pressed && isDown {
                isDown = false
                onKeyUp?()
            }
        case .keyDown where !isDown:
            isDown = true
            onKeyDown?()
        case .keyUp where isDown:
            isDown = false
            onKeyUp?()
        default:
            break
        }
    }

    func stop() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        tap = nil
        source = nil
        isDown = false
    }

    /// True if the tap was created (accessibility granted).
    var isActive: Bool { tap != nil }
}
