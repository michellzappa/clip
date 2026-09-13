import Foundation

/// One remembered pasteboard entry. Text only, on purpose: that is what a
/// clipboard history is for, and it keeps the store small and greppable.
struct Clipping: Codable, Equatable, Identifiable, Sendable {
    var id: UUID
    var text: String
    var sourceBundleID: String?
    var sourceName: String?
    var copiedAt: Date

    init(text: String, sourceBundleID: String?, sourceName: String?, copiedAt: Date = .now) {
        self.id = UUID()
        self.text = text
        self.sourceBundleID = sourceBundleID
        self.sourceName = sourceName
        self.copiedAt = copiedAt
    }

    /// One line, whitespace collapsed, for menus and rows.
    func preview(maxLength: Int) -> String {
        let collapsed = text
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: " ⏎ ")
        guard collapsed.count > maxLength else { return collapsed }
        return String(collapsed.prefix(maxLength)).trimmingCharacters(in: .whitespaces) + "…"
    }

    /// Without surrounding whitespace — a trailing newline is not a second line.
    var trimmed: Substring { text[...].trimmingCharacters(in: .whitespacesAndNewlines)[...] }

    var lineCount: Int {
        trimmed.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).count
    }

    var characterCount: Int { trimmed.count }
}
