import AppKit
import Combine
import Foundation

/// Newest-first clipping history plus settings, persisted as JSON under
/// Application Support (history) and UserDefaults (settings). Same shape as
/// Cargo's store: one in-memory value, one file, saves coalesced.
@MainActor
final class ClippingStore: ObservableObject {
    @Published private(set) var clippings: [Clipping] = []
    @Published var settings: StrataSettings {
        didSet {
            guard settings != oldValue else { return }
            settings.save()
            trim()
        }
    }

    private let fileURL: URL
    private var saveWorkItem: DispatchWorkItem?

    init(directory: URL? = nil) {
        settings = StrataSettings.load()
        let base = directory ?? FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Strata", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        fileURL = base.appendingPathComponent("clippings.json")
        if let data = try? Data(contentsOf: fileURL),
           let decoded = try? Self.decoder.decode([Clipping].self, from: data) {
            clippings = decoded
        }
    }

    /// Records a copy. A repeat of an existing entry moves it to the top rather
    /// than duplicating it — the history is "what I've had", not a log.
    func add(text: String, sourceBundleID: String?, sourceName: String?) {
        var next = clippings.filter { $0.text != text }
        next.insert(Clipping(text: text, sourceBundleID: sourceBundleID, sourceName: sourceName), at: 0)
        clippings = next
        trim()
        scheduleSave()
    }

    /// Moves a re-used clipping to the top, like a fresh copy would.
    func promote(_ clipping: Clipping) {
        guard let index = clippings.firstIndex(where: { $0.id == clipping.id }), index != 0 else { return }
        var next = clippings
        let item = next.remove(at: index)
        next.insert(item, at: 0)
        clippings = next
        scheduleSave()
    }

    func remove(_ clipping: Clipping) {
        clippings.removeAll { $0.id == clipping.id }
        scheduleSave()
    }

    func clear() {
        clippings = []
        scheduleSave()
    }

    func update(_ block: (inout StrataSettings) -> Void) {
        var next = settings
        block(&next)
        settings = next
    }

    private func trim() {
        let limit = max(1, settings.historyLimit)
        if clippings.count > limit {
            clippings = Array(clippings.prefix(limit))
            scheduleSave()
        }
    }

    private func scheduleSave() {
        saveWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in self?.saveNow() }
        saveWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: item)
    }

    func saveNow() {
        saveWorkItem?.cancel()
        saveWorkItem = nil
        do {
            let data = try Self.encoder.encode(clippings)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            NSLog("Strata: save failed: \(error)")
        }
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
