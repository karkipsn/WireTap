import Foundation

// MARK: - TRACER-013: WireTapReport

/// Release-safe diagnostic report builder for BLE and NFC events.
///
/// Accepts events the calling app explicitly feeds it, applies registered
/// decoders and device-name anonymization, and emits a `.wiretapsession`
/// JSON compatible with the WireTap toolchain.
///
/// **No network/HTTP data is accepted** — `NetworkEntry` has no add path.
/// The emitted session always has `network: []`.
///
/// **No passive capture** — no observers are installed. The caller controls
/// exactly which events enter the report.
///
/// **Ephemeral** — data lives in memory only. No disk writes, no persistence.
///
/// Typical usage:
/// ```swift
/// import WireTapCore
///
/// let report = WireTapReport(app: AppInfo(...))
/// Ms2Decoders.registerAll(on: report)              // BleDecoderRegistry
/// bleHistory.forEach { report.add(ble: $0.asWireTapEntry()) }
/// nfcHistory.forEach { report.add(nfc: $0.asWireTapEntry()) }
/// let data = try report.exportData()               // .wiretapsession JSON
/// ```
@MainActor
public final class WireTapReport: BleDecoderRegistry {

    // MARK: Stored state

    private let app: AppInfo
    private let environment: EnvInfo
    private let privacy: WireTapPrivacyLevel
    private var bleEntries: [BleEntry] = []
    private var nfcEntries: [NfcEntry] = []
    private var decoders: [String: @Sendable (Data) -> [String: String]] = [:]

    // MARK: Init

    public init(
        app: AppInfo,
        environment: EnvInfo? = nil,
        privacy: WireTapPrivacyLevel = .standard
    ) {
        self.app = app
        self.environment = environment ?? EnvInfo.current()
        self.privacy = privacy
    }

    // MARK: BleDecoderRegistry

    public func registerDecoder(
        forCharacteristic uuid: String,
        _ decode: @escaping @Sendable (Data) -> [String: String]
    ) {
        decoders[uuid.lowercased()] = decode
    }

    // MARK: Event ingestion

    /// Add a BLE event. Decoders and anonymization are applied at `build()` time.
    public func add(ble entry: BleEntry) {
        bleEntries.append(entry)
    }

    /// Add an NFC event.
    public func add(nfc entry: NfcEntry) {
        nfcEntries.append(entry)
    }

    // MARK: Build

    /// Apply decoders and privacy anonymization, then return an immutable
    /// `WireTapSession`. Non-destructive — safe to call multiple times.
    /// `network` is always `[]`.
    public func build() -> WireTapSession {
        let sortedBle = bleEntries
            .map { applyDecoders($0) }
            .map { anonymize($0) }
            .sorted { $0.date < $1.date }
        let sortedNfc = nfcEntries.sorted { $0.date < $1.date }

        let dates = sortedBle.map(\.date) + sortedNfc.map(\.date)
        let range: WireTapDateRange? = dates.isEmpty ? nil
            : WireTapDateRange(
                start: WireTapISO.string(dates.min()!),
                end:   WireTapISO.string(dates.max()!)
              )

        return WireTapSession(
            schemaVersion: wiretapSchemaMajor,
            exportedAt: WireTapISO.string(Date()),
            app: app,
            environment: environment,
            range: range,
            network: [],
            ble: sortedBle.map(BleRecord.init),
            nfc: sortedNfc.map(NfcRecord.init)
        )
    }

    // MARK: Export

    /// Encode the session as `.wiretapsession` JSON.
    public func exportData() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(build())
    }

    /// Render the session as LLM-optimized text (TRACER-003 format).
    public func exportForLLM(_ options: LLMExportOptions = .init()) -> String {
        WireTap.exportForLLM(build(), options: options)
    }

    // MARK: Private helpers

    /// Mirror of BleStore.decode() — runs the registered decoder for this entry's UUID.
    private func applyDecoders(_ entry: BleEntry) -> BleEntry {
        guard entry.decoded == nil,
              let data = entry.data,
              let uuid = entry.uuid,
              let decoder = decoders[uuid.lowercased()] else { return entry }
        let fields = decoder(data)
        return fields.isEmpty ? entry : entry.withDecoded(fields)
    }

    /// Truncate device name to last 4 chars when privacy == .standard.
    /// Characteristic UUIDs are kept in full (they identify protocols, not people).
    private func anonymize(_ entry: BleEntry) -> BleEntry {
        guard privacy == .standard, let device = entry.device, device.count > 4 else {
            return entry
        }
        let truncated = "***" + device.suffix(4)
        return BleEntry(
            id: entry.id, date: entry.date, type: entry.type,
            uuid: entry.uuid, device: truncated,
            data: entry.data, detail: entry.detail,
            error: entry.error, decoded: entry.decoded
        )
    }
}
