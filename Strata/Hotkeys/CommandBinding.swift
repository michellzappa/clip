import Foundation

/// A global shortcut as the Carbon hotkey API wants it: hardware key code plus
/// Carbon modifier flags. Same type as Tessellate's so `ShortcutDisplay` and
/// `ShortcutRecorder` are shared verbatim.
struct CommandBinding: Codable, Equatable, Hashable, Sendable {
    var keyCode: UInt16
    var modifiers: UInt

    init(keyCode: UInt16, modifiers: UInt) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }
}
