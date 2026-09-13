import AppKit
import HouseKit

extension SettingsWindowController {
    /// History · General · About, the house order.
    static func clip(store: ClippingStore) -> SettingsWindowController {
        SettingsWindowController(appName: "Clip", pages: [
            SettingsPage("History", symbol: "square.stack.3d.up", controller: HistoryPage(store: store)),
            SettingsPage("General", symbol: "gearshape", controller: GeneralPage(
                launchAtLogin: (get: { store.settings.launchAtLogin }, set: { value in store.update { $0.launchAtLogin = value } }),
                showMenuBarIcon: (get: { store.settings.showMenuBarIcon }, set: { value in store.update { $0.showMenuBarIcon = value } }),
                permissions: [.accessibility]
            )),
            SettingsPage("About", symbol: "info.circle", controller: AboutPage(
                appName: "Clip",
                tagline: "Layers of what you copied, newest on top.",
                links: [("GitHub", URL(string: "https://github.com/michellzappa/clip")!)]
            ))
        ])
    }
}
