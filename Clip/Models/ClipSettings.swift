import Carbon.HIToolbox
import Foundation
import HouseKit

struct ClipSettings: Codable, Equatable, Sendable {
    /// ⇧⌘V, what Flycut used. Quit Flycut before running Clip or they fight over it.
    var hotkey: KeyBinding? = KeyBinding(keyCode: UInt16(kVK_ANSI_V), modifiers: UInt(cmdKey | shiftKey))
    var historyLimit: Int = 100
    var menuItemCount: Int = 10
    var menuItemLength: Int = 48
    /// Bundle identifiers whose copies are never recorded (password managers, etc).
    var ignoredBundleIDs: [String] = ["com.1password.1password", "com.apple.keychainaccess"]
    var launchAtLogin: Bool = false
    var showMenuBarIcon: Bool = true

    static let defaultsKey = "clip.settings"

    static func load(from defaults: UserDefaults = .standard) -> ClipSettings {
        guard let data = defaults.data(forKey: defaultsKey),
              let settings = try? JSONDecoder().decode(ClipSettings.self, from: data)
        else { return ClipSettings() }
        return settings
    }

    func save(to defaults: UserDefaults = .standard) {
        if let data = try? JSONEncoder().encode(self) {
            defaults.set(data, forKey: Self.defaultsKey)
        }
    }
}
