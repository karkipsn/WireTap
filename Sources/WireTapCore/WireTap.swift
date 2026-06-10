import Foundation
import Combine

// MARK: - NetworkStore

@MainActor
public final class NetworkStore: ObservableObject {
    @Published public private(set) var entries: [NetworkEntry] = []
    public var maxEntries: Int = 500
    private var writer: PersistenceWriter<NetworkEntry>?

    public func record(_ entry: NetworkEntry) {
        entries.insert(entry, at: 0)
        if entries.count > maxEntries { entries.removeLast(entries.count - maxEntries) }
        // Redact before the entry ever reaches disk (TRACER-001 invariant).
        writer?.append(WireTapRedaction.redacted(entry, config: WireTap.redaction))
    }

    public func clear() {
        entries.removeAll()
        writer?.truncate()
    }

    /// Attach disk persistence and reload any previously persisted entries (newest first).
    func enableDiskPersistence(fileURL: URL, fileCap: Int) {
        guard let writer = PersistenceWriter<NetworkEntry>(fileURL: fileURL, cap: fileCap) else { return }
        self.writer = writer
        let (items, _) = writer.loadAll()
        entries = Array(items.reversed().prefix(maxEntries))
    }

    /// Block until pending disk writes complete. Test-only.
    func flushPersistenceForTesting() { writer?.flush() }
}

// MARK: - BleStore

@MainActor
public final class BleStore: ObservableObject {
    @Published public private(set) var entries: [BleEntry] = []
    public var maxEntries: Int = 1000
    private var writer: PersistenceWriter<BleEntry>?
    private var decoders: [String: @Sendable (Data) -> [String: String]] = [:]

    public func log(_ entry: BleEntry) {
        let decoded = decode(entry)
        entries.insert(decoded, at: 0)
        if entries.count > maxEntries { entries.removeLast(entries.count - maxEntries) }
        writer?.append(decoded)
    }

    /// Apply a registered decoder (if any) to produce named fields for this entry.
    private func decode(_ entry: BleEntry) -> BleEntry {
        guard entry.decoded == nil,
              let data = entry.data,
              let uuid = entry.uuid,
              let decoder = decoders[uuid.lowercased()] else { return entry }
        let fields = decoder(data)
        return fields.isEmpty ? entry : entry.withDecoded(fields)
    }

    /// Register a decoder for a characteristic UUID (TRACER-005). When a logged BLE
    /// entry carries data for this UUID, its bytes become named fields shown in the
    /// inspector, the session export, and the LLM export. Matching is case-insensitive.
    ///
    /// The closure is retained for the app's lifetime (until `removeDecoder`/`clearDecoders`).
    /// Capture `[weak self]` if it references a view controller / manager, to avoid pinning it.
    public func registerDecoder(forCharacteristic uuid: String,
                                _ decode: @escaping @Sendable (Data) -> [String: String]) {
        decoders[uuid.lowercased()] = decode
    }

    /// Remove a previously registered decoder.
    public func removeDecoder(forCharacteristic uuid: String) {
        decoders[uuid.lowercased()] = nil
    }

    /// Remove all registered decoders.
    public func clearDecoders() {
        decoders.removeAll()
    }

    public func clear() {
        entries.removeAll()
        writer?.truncate()
    }

    func enableDiskPersistence(fileURL: URL, fileCap: Int) {
        guard let writer = PersistenceWriter<BleEntry>(fileURL: fileURL, cap: fileCap) else { return }
        self.writer = writer
        let (items, skipped) = writer.loadAll()
        var loaded = Array(items.reversed())
        if skipped > 0 {
            loaded.insert(BleEntry(type: .info, detail: "skipped \(skipped) corrupt persisted line(s)"), at: 0)
        }
        entries = Array(loaded.prefix(maxEntries))
    }

    func flushPersistenceForTesting() { writer?.flush() }
}

// MARK: - NfcStore

@MainActor
public final class NfcStore: ObservableObject {
    @Published public private(set) var entries: [NfcEntry] = []
    public var maxEntries: Int = 200
    private var writer: PersistenceWriter<NfcEntry>?

    public func log(_ entry: NfcEntry) {
        entries.insert(entry, at: 0)
        if entries.count > maxEntries { entries.removeLast(entries.count - maxEntries) }
        writer?.append(entry)
    }

    public func clear() {
        entries.removeAll()
        writer?.truncate()
    }

    func enableDiskPersistence(fileURL: URL, fileCap: Int) {
        guard let writer = PersistenceWriter<NfcEntry>(fileURL: fileURL, cap: fileCap) else { return }
        self.writer = writer
        let (items, _) = writer.loadAll()
        entries = Array(items.reversed().prefix(maxEntries))
    }

    func flushPersistenceForTesting() { writer?.flush() }
}

// MARK: - WireTap (main entry point)

/// In-app debugger for HTTP traffic and BLE events.
///
/// Usage from your HTTP client:
/// ```swift
/// await WireTap.network.record(NetworkEntry(...))
/// ```
///
/// Usage from your BLE manager:
/// ```swift
/// await WireTap.ble.log(BleEntry(type: .connected, device: name))
/// ```
///
/// Present the inspector anywhere in your debug UI:
/// ```swift
/// NavigationLink("WireTap") { WireTapView() }
/// ```
@MainActor
public final class WireTap {
    public static let network = NetworkStore()
    public static let ble     = BleStore()
    public static let nfc     = NfcStore()

    /// Active redaction rules (TRACER-010). Set once at startup to extend the defaults.
    public static var redaction: WireTapRedactionConfig = .default

    private init() {}

    /// Configure where WireTap stores captured entries. Call once at startup, before
    /// the first capture. Default is `.inMemory` (no IO, lost on relaunch).
    ///
    /// ```swift
    /// #if DEBUG
    /// WireTap.configure(storage: .disk())   // survives relaunch
    /// #endif
    /// ```
    public static func configure(storage: WireTapStorage) {
        switch storage {
        case .inMemory:
            break // default behavior; nothing to attach
        case let .disk(directory, fileCap):
            guard let dir = directory ?? defaultDirectory() else {
                wiretapLog.error("WireTap.configure(.disk): no writable directory; staying in-memory")
                return
            }
            network.enableDiskPersistence(fileURL: dir.appendingPathComponent("network.jsonl"), fileCap: fileCap)
            ble.enableDiskPersistence(fileURL: dir.appendingPathComponent("ble.jsonl"), fileCap: fileCap)
            nfc.enableDiskPersistence(fileURL: dir.appendingPathComponent("nfc.jsonl"), fileCap: fileCap)
        }
    }

    /// Clears all captured data from all stores (and truncates any on-disk files).
    public static func clearAll() {
        network.clear()
        ble.clear()
        nfc.clear()
    }

    private static func defaultDirectory() -> URL? {
        guard let base = try? FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true
        ) else { return nil }
        return base.appendingPathComponent("WireTap", isDirectory: true)
    }
}
