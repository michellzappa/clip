import AppKit

/// The history picker: a floating, non-activating panel so the frontmost app
/// keeps focus and receives the paste. Type to filter, ↑↓ to move, ⏎ or click
/// to paste, ⎋ to dismiss. The hotkey steps the selection while it is open.
@MainActor
final class PickerPanel: NSPanel, NSTableViewDataSource, NSTableViewDelegate, NSSearchFieldDelegate {
    private let store: ClippingStore
    private let onPick: (Clipping) -> Void
    private let searchField = NSSearchField()
    private let tableView = NSTableView()
    private let scrollView = NSScrollView()
    private let emptyLabel = NSTextField(labelWithString: "Nothing copied yet")
    private var filtered: [Clipping] = []

    init(store: ClippingStore, onPick: @escaping (Clipping) -> Void) {
        self.store = store
        self.onPick = onPick
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 400),
            styleMask: [.nonactivatingPanel, .titled, .fullSizeContentView, .resizable],
            backing: .buffered,
            defer: false
        )
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        // Transient picker: ⎋ or clicking away closes it, so no traffic lights.
        for button in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            standardWindowButton(button)?.isHidden = true
        }
        isMovableByWindowBackground = true
        level = .floating
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        animationBehavior = .utilityWindow
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        minSize = NSSize(width: 360, height: 240)
        buildContent()
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    // MARK: - Presentation

    func present() {
        searchField.stringValue = ""
        reload()
        centerOnMouseScreen()
        makeKeyAndOrderFront(nil)
        makeFirstResponder(searchField)
        select(row: 0)
    }

    func dismiss() {
        orderOut(nil)
    }

    /// Hotkey pressed while open: walk down the list, wrapping.
    func stepSelection(_ delta: Int) {
        guard !filtered.isEmpty else { return }
        let current = tableView.selectedRow
        let next = ((current < 0 ? -1 : current) + delta + filtered.count) % filtered.count
        select(row: next)
    }

    private func centerOnMouseScreen() {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return }
        let origin = NSPoint(
            x: visible.midX - frame.width / 2,
            y: visible.midY - frame.height / 2 + visible.height * 0.08
        )
        setFrameOrigin(origin)
    }

    // MARK: - Layout

    private func buildContent() {
        let effect = NSVisualEffectView()
        effect.material = .popover
        effect.blendingMode = .behindWindow
        effect.state = .active
        contentView = effect

        searchField.placeholderString = "Search history"
        searchField.font = .systemFont(ofSize: 15)
        searchField.focusRingType = .none
        searchField.delegate = self
        searchField.sendsSearchStringImmediately = true
        searchField.sendsWholeSearchString = false
        searchField.translatesAutoresizingMaskIntoConstraints = false

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("clipping"))
        column.resizingMask = .autoresizingMask
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.rowHeight = 46
        tableView.style = .inset
        tableView.selectionHighlightStyle = .regular
        tableView.allowsEmptySelection = true
        tableView.intercellSpacing = NSSize(width: 0, height: 2)
        tableView.dataSource = self
        tableView.delegate = self
        tableView.target = self
        tableView.action = #selector(rowClicked)
        tableView.refusesFirstResponder = true
        tableView.setAccessibilityLabel("Clipboard history")

        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        emptyLabel.textColor = .secondaryLabelColor
        emptyLabel.alignment = .center
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false

        let separator = NSBox()
        separator.boxType = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false

        effect.addSubview(searchField)
        effect.addSubview(separator)
        effect.addSubview(scrollView)
        effect.addSubview(emptyLabel)
        NSLayoutConstraint.activate([
            searchField.topAnchor.constraint(equalTo: effect.topAnchor, constant: 12),
            searchField.leadingAnchor.constraint(equalTo: effect.leadingAnchor, constant: 12),
            searchField.trailingAnchor.constraint(equalTo: effect.trailingAnchor, constant: -12),
            separator.topAnchor.constraint(equalTo: searchField.bottomAnchor, constant: 10),
            separator.leadingAnchor.constraint(equalTo: effect.leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: effect.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: separator.bottomAnchor, constant: 4),
            scrollView.leadingAnchor.constraint(equalTo: effect.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: effect.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: effect.bottomAnchor, constant: -6),
            emptyLabel.centerXAnchor.constraint(equalTo: scrollView.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: scrollView.centerYAnchor)
        ])
    }

    // MARK: - Data

    private func reload() {
        let query = searchField.stringValue.trimmingCharacters(in: .whitespaces)
        filtered = query.isEmpty
            ? store.clippings
            : store.clippings.filter { $0.text.localizedCaseInsensitiveContains(query) }
        tableView.reloadData()
        emptyLabel.stringValue = store.clippings.isEmpty ? "Nothing copied yet" : "No matches"
        emptyLabel.isHidden = !filtered.isEmpty
    }

    private func select(row: Int) {
        guard row >= 0, row < filtered.count else {
            tableView.deselectAll(nil)
            return
        }
        tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        tableView.scrollRowToVisible(row)
    }

    private func pickSelected() {
        let row = tableView.selectedRow
        guard row >= 0, row < filtered.count else { return }
        onPick(filtered[row])
    }

    private func deleteSelected() {
        let row = tableView.selectedRow
        guard row >= 0, row < filtered.count else { return }
        store.remove(filtered[row])
        reload()
        select(row: min(row, filtered.count - 1))
    }

    @objc private func rowClicked() {
        guard tableView.clickedRow >= 0 else { return }
        select(row: tableView.clickedRow)
        pickSelected()
    }

    // MARK: - NSTableViewDataSource / Delegate

    func numberOfRows(in tableView: NSTableView) -> Int { filtered.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let identifier = NSUserInterfaceItemIdentifier("ClippingRow")
        let view = tableView.makeView(withIdentifier: identifier, owner: nil) as? ClippingRowView ?? ClippingRowView(identifier: identifier)
        view.configure(filtered[row], menuLength: store.settings.menuItemLength * 2)
        return view
    }

    // MARK: - NSSearchFieldDelegate

    func controlTextDidChange(_ notification: Notification) {
        reload()
        select(row: 0)
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        switch selector {
        case #selector(NSResponder.moveDown(_:)):
            stepSelection(1)
        case #selector(NSResponder.moveUp(_:)):
            stepSelection(-1)
        case #selector(NSResponder.insertNewline(_:)):
            pickSelected()
        case #selector(NSResponder.cancelOperation(_:)):
            dismiss()
        case #selector(NSResponder.deleteToBeginningOfLine(_:)), #selector(NSResponder.deleteForward(_:)) where searchField.stringValue.isEmpty:
            deleteSelected()
        default:
            return false
        }
        return true
    }

    override func cancelOperation(_ sender: Any?) {
        dismiss()
    }

    override func resignKey() {
        super.resignKey()
        // Clicking elsewhere means "never mind".
        orderOut(nil)
    }
}

/// Two lines of the clipping, then source app and age, small and secondary.
private final class ClippingRowView: NSTableCellView {
    private let title = NSTextField(wrappingLabelWithString: "")
    private let detail = NSTextField(labelWithString: "")

    init(identifier: NSUserInterfaceItemIdentifier) {
        super.init(frame: .zero)
        self.identifier = identifier
        title.font = .systemFont(ofSize: 13)
        title.maximumNumberOfLines = 1
        title.lineBreakMode = .byTruncatingTail
        title.isSelectable = false
        title.translatesAutoresizingMaskIntoConstraints = false
        detail.font = .systemFont(ofSize: 11)
        detail.textColor = .secondaryLabelColor
        detail.lineBreakMode = .byTruncatingTail
        detail.translatesAutoresizingMaskIntoConstraints = false
        addSubview(title)
        addSubview(detail)
        NSLayoutConstraint.activate([
            title.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            title.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            title.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            detail.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 2),
            detail.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            detail.trailingAnchor.constraint(equalTo: title.trailingAnchor)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func configure(_ clipping: Clipping, menuLength: Int) {
        title.stringValue = clipping.preview(maxLength: menuLength)
        var parts: [String] = []
        if let source = clipping.sourceName { parts.append(source) }
        parts.append(Self.relative.localizedString(for: clipping.copiedAt, relativeTo: .now))
        let lines = clipping.lineCount
        if lines > 1 { parts.append("\(lines) lines") }
        parts.append("\(clipping.characterCount) chars")
        detail.stringValue = parts.joined(separator: " · ")
    }

    private static let relative: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter
    }()
}
