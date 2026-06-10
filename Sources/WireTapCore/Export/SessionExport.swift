import Foundation
#if canImport(UIKit)
import UIKit
#endif

// MARK: - TRACER-002 — Unified Session Export / Import

/// Current export schema major version. Bump only on breaking changes.
let wiretapSchemaMajor = 1

/// ISO-8601 with fractional seconds — the timestamp format in the `.wiretapsession`
/// contract (matches what `wiretap-mcp` parses).
enum WireTapISO {
    static let formatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    static func string(_ date: Date) -> String { formatter.string(from: date) }
}

// MARK: - Session value types (the `.wiretapsession` JSON shape)

public struct AppInfo: Codable, Sendable {
    public let bundleId: String
    public let name: String?
    public let version: String
    public let build: String?

    public init(bundleId: String, name: String? = nil, version: String, build: String? = nil) {
        self.bundleId = bundleId
        self.name = name
        self.version = version
        self.build = build
    }

    /// App metadata read from the main bundle. Public so release consumers can
    /// pass it to `WireTapReport` (TRACER-013).
    public static func current() -> AppInfo {
        let info = Bundle.main.infoDictionary ?? [:]
        return AppInfo(
            bundleId: Bundle.main.bundleIdentifier ?? "unknown",
            name: info["CFBundleName"] as? String,
            version: (info["CFBundleShortVersionString"] as? String) ?? "0",
            build: info["CFBundleVersion"] as? String
        )
    }
}

public struct EnvInfo: Codable, Sendable {
    public let os: String
    public let osVersion: String
    public let device: String?
    public let locale: String?

    public init(os: String, osVersion: String, device: String? = nil, locale: String? = nil) {
        self.os = os
        self.osVersion = osVersion
        self.device = device
        self.locale = locale
    }

    /// Environment metadata for the current process. Public so release consumers
    /// can pass it to `WireTapReport` (TRACER-013).
    public static func current() -> EnvInfo {
        #if os(iOS)
        let os = "iOS"
        #elseif os(macOS)
        let os = "macOS"
        #else
        let os = "unknown"
        #endif
        #if canImport(UIKit)
        let device = UIDevice.current.model
        #else
        let device: String? = nil
        #endif
        return EnvInfo(
            os: os,
            osVersion: ProcessInfo.processInfo.operatingSystemVersionString,
            device: device,
            locale: Locale.current.identifier
        )
    }
}

public struct WireTapDateRange: Codable, Sendable {
    public let start: String // ISO-8601
    public let end: String
}

/// One captured HTTP request/response, in export shape.
public struct NetworkRecord: Codable, Sendable {
    public let id: String
    public let timestamp: String
    public let method: String
    public let url: String
    public let requestHeaders: [String: String]
    public let requestBody: String?
    public let statusCode: Int?
    public let responseHeaders: [String: String]
    public let responseBody: String?
    public let durationMs: Int
    public let error: String?

    init(_ e: NetworkEntry) {
        id = e.id.uuidString
        timestamp = WireTapISO.string(e.date)
        method = e.method
        url = e.url
        requestHeaders = e.requestHeaders
        requestBody = e.requestBody
        statusCode = e.statusCode
        responseHeaders = e.responseHeaders
        responseBody = e.responseBody
        durationMs = e.durationMs
        error = e.error
    }
}

public struct BleRecord: Codable, Sendable {
    public let id: String
    public let timestamp: String
    public let type: String // event-type case name, e.g. "disconnected", "authFailed"
    public let uuid: String?
    public let device: String?
    public let hex: String?
    public let detail: String?
    public let error: String?
    public let decoded: [String: String]?

    init(_ e: BleEntry) {
        id = e.id.uuidString
        timestamp = WireTapISO.string(e.date)
        type = String(describing: e.type)
        uuid = e.uuid
        device = e.device
        hex = WireTapHex.compact(e.data)
        detail = e.detail
        error = e.error
        decoded = e.decoded
    }
}

public struct NfcRecord: Codable, Sendable {
    public let id: String
    public let timestamp: String
    public let type: String
    public let descriptor: String?
    public let hex: String?
    public let detail: String?
    public let error: String?

    init(_ e: NfcEntry) {
        id = e.id.uuidString
        timestamp = WireTapISO.string(e.date)
        type = String(describing: e.type)
        descriptor = e.descriptor
        hex = WireTapHex.compact(e.data)
        detail = e.detail
        error = e.error
    }
}

/// A complete captured session — the `.wiretapsession` document.
public struct WireTapSession: Codable, Sendable {
    public let schemaVersion: Int
    public let exportedAt: String
    public let app: AppInfo
    public let environment: EnvInfo
    public let range: WireTapDateRange?
    public let network: [NetworkRecord]
    public let ble: [BleRecord]
    public let nfc: [NfcRecord]
}

/// One event projected onto the unified, cross-stream timeline.
public struct TimelineItem: Sendable {
    public enum Kind: String, Sendable { case network, ble, nfc }
    public let timestamp: String
    public let kind: Kind
    public let summary: String
    public let entryId: UUID
}

public enum WireTapSessionError: Error, Equatable {
    case unsupportedSchema(version: Int)
    case decodeFailed(String)
}

enum WireTapHex {
    static func compact(_ data: Data?) -> String? {
        guard let data, !data.isEmpty else { return nil }
        return data.map { String(format: "%02x", $0) }.joined()
    }
}

// MARK: - WireTap export / import / timeline

public extension WireTap {

    /// Snapshot all three stores into a session value (entries ascending by time,
    /// network headers redacted).
    static func makeSession() -> WireTapSession {
        let net = network.entries.map { WireTapRedaction.redacted($0, config: Self.redaction) }.sorted { $0.date < $1.date }
        let bleEntries = ble.entries.sorted { $0.date < $1.date }
        let nfcEntries = nfc.entries.sorted { $0.date < $1.date }

        let dates = net.map(\.date) + bleEntries.map(\.date) + nfcEntries.map(\.date)
        let range: WireTapDateRange? = dates.isEmpty ? nil
            : WireTapDateRange(start: WireTapISO.string(dates.min()!), end: WireTapISO.string(dates.max()!))

        return WireTapSession(
            schemaVersion: wiretapSchemaMajor,
            exportedAt: WireTapISO.string(Date()),
            app: .current(),
            environment: .current(),
            range: range,
            network: net.map(NetworkRecord.init),
            ble: bleEntries.map(BleRecord.init),
            nfc: nfcEntries.map(NfcRecord.init)
        )
    }

    /// Encode the current capture as pretty `.wiretapsession` JSON.
    static func exportSessionData() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(makeSession())
    }

    /// Decode a `.wiretapsession` for read-only inspection. Does not touch live stores.
    static func importSession(_ data: Data) throws -> WireTapSession {
        struct SchemaProbe: Decodable { let schemaVersion: Int }
        let probe: SchemaProbe
        do {
            probe = try JSONDecoder().decode(SchemaProbe.self, from: data)
        } catch {
            throw WireTapSessionError.decodeFailed("missing or invalid schemaVersion")
        }
        guard probe.schemaVersion <= wiretapSchemaMajor else {
            throw WireTapSessionError.unsupportedSchema(version: probe.schemaVersion)
        }
        do {
            return try JSONDecoder().decode(WireTapSession.self, from: data)
        } catch {
            throw WireTapSessionError.decodeFailed(String(describing: error))
        }
    }

    /// Merge all three streams into one ascending-time timeline. Ties are broken
    /// deterministically by kind, then entry id.
    static func timeline() -> [TimelineItem] {
        timelineEntries().map(\.item)
    }

    /// Date-aware timeline used by both `timeline()` and cross-radio correlation (TRACER-007).
    static func timelineEntries() -> [(date: Date, item: TimelineItem)] {
        var rows: [(date: Date, item: TimelineItem)] = []
        rows += network.entries.map {
            ($0.date, TimelineItem(timestamp: WireTapISO.string($0.date), kind: .network,
                                   summary: "\($0.method) \($0.url) \($0.statusLabel)", entryId: $0.id))
        }
        rows += ble.entries.map {
            let bits = [String(describing: $0.type), $0.uuid, $0.device, $0.detail, $0.error]
                .compactMap { $0 }.joined(separator: " ")
            return ($0.date, TimelineItem(timestamp: WireTapISO.string($0.date), kind: .ble, summary: bits, entryId: $0.id))
        }
        rows += nfc.entries.map {
            let bits = [String(describing: $0.type), $0.descriptor, $0.detail, $0.error]
                .compactMap { $0 }.joined(separator: " ")
            return ($0.date, TimelineItem(timestamp: WireTapISO.string($0.date), kind: .nfc, summary: bits, entryId: $0.id))
        }
        return rows.sorted { a, b in
            if a.item.timestamp != b.item.timestamp { return a.item.timestamp < b.item.timestamp }
            if a.item.kind.rawValue != b.item.kind.rawValue { return a.item.kind.rawValue < b.item.kind.rawValue }
            return a.item.entryId.uuidString < b.item.entryId.uuidString
        }
    }
}
