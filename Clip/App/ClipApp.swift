import AppKit
import Combine
import HouseKit

@main
@MainActor
final class ClipAppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let store = ClippingStore()
    private lazy var watcher = PasteboardWatcher(store: store)
    private let hotkey = GlobalHotkey(signature: "CLIP")
    private lazy var panel = PickerPanel(store: store) { [weak self] clipping in self?.paste(clipping) }
    private lazy var settingsWindowController = SettingsWindowController.clip(store: store)
    private var statusItem: NSStatusItem!
    private var statusMenu: NSMenu!
    private var cancellables = Set<AnyCancellable>()
    private var promptedForAccessibility = false

    static func main() {
        let application = NSApplication.shared
        let delegate = ClipAppDelegate()
        application.delegate = delegate
        application.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.accessory)
        NSApplication.shared.mainMenu = makeMainMenu()

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.image = MenuBarPlate.image(glyph: HouseGlyphs.clip)
            button.imagePosition = .imageOnly
            button.setAccessibilityLabel("Clip menu")
            button.toolTip = "Clip"
        }
        statusMenu = NSMenu()
        statusMenu.delegate = self
        statusItem.menu = statusMenu
        rebuildStatusMenu()

        hotkey.onPress = { [weak self] in self?.activate() }
        applySettings(store.settings)
        store.$settings
            .dropFirst()
            .removeDuplicates()
            .sink { [weak self] settings in self?.applySettings(settings) }
            .store(in: &cancellables)

        watcher.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        store.saveNow()
    }

    /// `clip://show` opens the picker, `clip://settings` the settings window —
    /// for Shortcuts, Raycast, and the like.
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls where url.scheme == "clip" {
            switch url.host ?? url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/")) {
            case "show": panel.present()
            case "settings": settingsWindowController.show()
            default: break
            }
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { settingsWindowController.show() }
        return true
    }

    private func applySettings(_ settings: ClipSettings) {
        hotkey.register(settings.hotkey)
        statusItem.isVisible = settings.showMenuBarIcon
        if LaunchAtLogin.isEnabled != settings.launchAtLogin {
            do {
                try LaunchAtLogin.setEnabled(settings.launchAtLogin)
            } catch {
                NSLog("Clip: launch at login failed: \(error)")
            }
        }
    }

    // MARK: - Hotkey / paste

    private func activate() {
        if panel.isVisible {
            panel.stepSelection(1)
        } else {
            panel.present()
        }
    }

    private func paste(_ clipping: Clipping) {
        panel.dismiss()
        store.promote(clipping)
        watcher.changeCountToSkip = Paster.place(clipping.text)
        guard Paster.isTrusted() else {
            if !promptedForAccessibility {
                promptedForAccessibility = true
                Paster.requestTrust()
            }
            return
        }
        // Let the previous key window take focus back before ⌘V lands.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            Paster.sendPasteKeystroke()
        }
    }

    // MARK: - Status menu

    func menuWillOpen(_ menu: NSMenu) {
        guard menu === statusMenu else { return }
        rebuildStatusMenu()
    }

    /// Action-first, same shape as Tessellate and Cargo: header, the things
    /// you came for, then Settings / Launch at Login / Quit.
    private func rebuildStatusMenu() {
        statusMenu.removeAllItems()
        let count = store.clippings.count
        let header = count == 0 ? "Clip" : "\(count) clipping\(count == 1 ? "" : "s")"
        statusMenu.addItem(StatusMenu.sectionHeader(header))

        let recent = store.clippings.prefix(max(0, store.settings.menuItemCount))
        for (index, clipping) in recent.enumerated() {
            let item = NSMenuItem(
                title: clipping.preview(maxLength: store.settings.menuItemLength),
                action: #selector(pasteMenuItem(_:)),
                keyEquivalent: index < 9 ? String(index + 1) : ""
            )
            item.keyEquivalentModifierMask = []
            item.representedObject = clipping.id
            item.toolTip = clipping.sourceName
            statusMenu.addItem(item)
        }
        if !recent.isEmpty {
            statusMenu.addItem(.separator())
        }

        let showItem = NSMenuItem(title: "Show History…", action: #selector(showPicker(_:)), keyEquivalent: "")
        if let binding = store.settings.hotkey {
            showItem.title = "Show History… \(binding.displayString)"
        }
        statusMenu.addItem(showItem)
        let clearItem = NSMenuItem(title: "Clear History", action: #selector(clearHistory(_:)), keyEquivalent: "")
        clearItem.isEnabled = count > 0
        statusMenu.addItem(clearItem)
        statusMenu.items.forEach { $0.target = self }
        StatusMenu.appendStandardTail(
            to: statusMenu,
            appName: "Clip",
            target: self,
            settings: #selector(showSettings(_:)),
            launchAtLogin: #selector(toggleLaunchAtLogin(_:)),
            launchAtLoginEnabled: store.settings.launchAtLogin,
            quit: #selector(quit(_:))
        )
    }

    private func makeMainMenu() -> NSMenu {
        let mainMenu = NSMenu()
        let appMenu = NSMenu(title: "Clip")
        appMenu.addItem(withTitle: "About Clip", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Settings…", action: #selector(showSettings(_:)), keyEquivalent: ",").target = self
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit Clip", action: #selector(quit(_:)), keyEquivalent: "q").target = self
        mainMenu.addItem(withTitle: "Clip", action: nil, keyEquivalent: "").submenu = appMenu

        // Text fields in Settings need these to respond to ⌘C/⌘V/⌘A.
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        mainMenu.addItem(withTitle: "Edit", action: nil, keyEquivalent: "").submenu = editMenu

        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        windowMenu.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        mainMenu.addItem(withTitle: "Window", action: nil, keyEquivalent: "").submenu = windowMenu
        NSApplication.shared.windowsMenu = windowMenu
        return mainMenu
    }

    // MARK: - Actions

    @objc private func pasteMenuItem(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? UUID,
              let clipping = store.clippings.first(where: { $0.id == id })
        else { return }
        paste(clipping)
    }

    @objc private func showPicker(_ sender: Any?) {
        panel.present()
    }

    @objc private func clearHistory(_ sender: Any?) {
        store.clear()
    }

    @objc private func showSettings(_ sender: Any?) {
        settingsWindowController.show()
    }

    @objc private func toggleLaunchAtLogin(_ sender: Any?) {
        store.update { $0.launchAtLogin.toggle() }
    }

    @objc private func quit(_ sender: Any?) {
        NSApp.terminate(nil)
    }
}
