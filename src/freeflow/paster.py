"""Paste text at cursor via CGEvent. Restores clipboard after."""
import time
import AppKit
from Quartz import (CGEventCreateKeyboardEvent, CGEventPost, kCGHIDEventTap,
                    kCGEventKeyDown, kCGEventKeyUp, kCGEventFlagMaskCommand)

def paste_text(text: str):
    """Put text on clipboard, simulate Cmd+V, restore original clipboard."""
    pb = AppKit.NSPasteboard.generalPasteboard()
    old = pb.stringForType_(AppKit.NSPasteboardTypeString)
    pb.clearContents()
    pb.setString_forType_(text, AppKit.NSPasteboardTypeString)
    time.sleep(0.05)

    v_down = CGEventCreateKeyboardEvent(None, 9, True)   # keycode 9 = 'v'
    v_up = CGEventCreateKeyboardEvent(None, 9, False)
    v_down.setFlags(kCGEventFlagMaskCommand)
    v_up.setFlags(kCGEventFlagMaskCommand)
    CGEventPost(kCGHIDEventTap, v_down)
    CGEventPost(kCGHIDEventTap, v_up)

    # restore clipboard
    time.sleep(0.15)
    if old:
        pb.clearContents()
        pb.setString_forType_(old, AppKit.NSPasteboardTypeString)
