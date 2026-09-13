import AppKit
import Carbon.HIToolbox
import HouseKit

/// Puts a clipping on the pasteboard and, with Accessibility granted, sends ⌘V
/// to the frontmost app. Without the grant it stops at the pasteboard — the
/// user pastes by hand and the app tells them why once.
@MainActor
enum Paster {
    /// Writes `text` to the pasteboard and returns the resulting change count so
    /// the watcher can ignore it.
    @discardableResult
    static func place(_ text: String) -> Int {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        return pasteboard.changeCount
    }

    /// Synthesizes ⌘V. Callers should give the previous key window a moment to
    /// regain focus after our panel closes.
    static func sendPasteKeystroke() {
        guard let source = CGEventSource(stateID: .combinedSessionState) else { return }
        let key = CGKeyCode(kVK_ANSI_V)
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: false)
        else { return }
        down.flags = .maskCommand
        up.flags = .maskCommand
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }
}
