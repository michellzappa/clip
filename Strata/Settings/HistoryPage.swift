import AppKit
import HouseKit

/// Strata's own settings page: the shortcut, how much to keep, what to ignore.
@MainActor
final class HistoryPage: SettingsForm, NSTableViewDataSource, NSTableViewDelegate {
    private let store: ClippingStore
    private let ignoredTable = NSTableView()
    private let removeButton = SettingsForm.button("Remove", target: nil, action: nil)
    private let storedLabel = SettingsForm.label("")
    private let clearButton = SettingsForm.button("Clear History", target: nil, action: nil)
    private var cancellable: Any?

    init(store: ClippingStore) {
        self.store = store
        super.init()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        section("Shortcut")
        let recorder = ShortcutRecorder(binding: store.settings.hotkey) { [store] value in
            store.update { settings in settings.hotkey = value }
        }
        recorder.requiresModifiers = true
        recorder.placeholder = "Record"
        row("Show history", recorder)
        note("Press it again while the list is open to step down. ⏎ pastes, ⎋ closes, ⌫ on an empty search forgets the selected item.")

        section("History")
        row("Remember", SettingsForm.stepper(value: store.settings.historyLimit, range: 10...1000, step: 10, format: { "\($0) clippings" }) { [store] value in
            store.update { settings in settings.historyLimit = value }
        })
        row("In the menu", SettingsForm.stepper(value: store.settings.menuItemCount, range: 0...30, format: { "\($0) items" }) { [store] value in
            store.update { settings in settings.menuItemCount = value }
        })
        row("Truncate at", SettingsForm.stepper(value: store.settings.menuItemLength, range: 20...120, step: 4, format: { "\($0) characters" }) { [store] value in
            store.update { settings in settings.menuItemLength = value }
        })
        clearButton.target = self
        clearButton.action = #selector(clearHistory)
        row("Stored", [storedLabel, clearButton])

        section("Ignored apps")
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("app"))
        ignoredTable.addTableColumn(column)
        ignoredTable.headerView = nil
        ignoredTable.rowHeight = 22
        ignoredTable.dataSource = self
        ignoredTable.delegate = self
        let scroll = NSScrollView()
        scroll.documentView = ignoredTable
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        scroll.widthAnchor.constraint(equalToConstant: SettingsForm.contentWidth).isActive = true
        scroll.heightAnchor.constraint(equalToConstant: 110).isActive = true
        row(nil, scroll)
        let add = SettingsForm.button("Add App…", target: self, action: #selector(addIgnoredApp))
        removeButton.target = self
        removeButton.action = #selector(removeIgnoredApp)
        removeButton.isEnabled = false
        row(nil, [add, removeButton])
        note("Copies made in these apps are never recorded. Password managers that mark their copies as concealed are skipped automatically.")

        cancellable = store.objectWillChange.sink { [weak self] _ in
            Task { @MainActor [weak self] in self?.refresh() }
        }
        refresh()
    }

    private func refresh() {
        let count = store.clippings.count
        storedLabel.stringValue = "\(count) clipping\(count == 1 ? "" : "s")"
        clearButton.isEnabled = count > 0
        ignoredTable.reloadData()
    }

    @objc private func clearHistory() {
        store.clear()
    }

    @objc private func addIgnoredApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.applicationBundle]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowsMultipleSelection = true
        panel.prompt = "Ignore"
        guard panel.runModal() == .OK else { return }
        let ids = panel.urls.compactMap { Bundle(url: $0)?.bundleIdentifier }
        store.update { settings in
            for id in ids where !settings.ignoredBundleIDs.contains(id) {
                settings.ignoredBundleIDs.append(id)
            }
        }
    }

    @objc private func removeIgnoredApp() {
        let row = ignoredTable.selectedRow
        guard store.settings.ignoredBundleIDs.indices.contains(row) else { return }
        store.update { $0.ignoredBundleIDs.remove(at: row) }
    }

    func numberOfRows(in tableView: NSTableView) -> Int { store.settings.ignoredBundleIDs.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let bundleID = store.settings.ignoredBundleIDs[row]
        let name = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
            .map { FileManager.default.displayName(atPath: $0.path).replacingOccurrences(of: ".app", with: "") }
        let label = SettingsForm.label(name.map { "\($0)  ·  \(bundleID)" } ?? bundleID)
        label.font = .systemFont(ofSize: 12)
        return label
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        removeButton.isEnabled = ignoredTable.selectedRow >= 0
    }
}
