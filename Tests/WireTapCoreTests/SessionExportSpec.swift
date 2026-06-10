import XCTest
@testable import WireTapCore

/// TRACER-002 — Unified Session Export / Import.
///
/// Each test maps 1:1 to an acceptance criterion in
/// `doc/specs/TRACER-002-session-export.md`. The exported JSON deliberately matches
/// the language-agnostic `.wiretapsession` contract that `wiretap-mcp` parses
/// (ISO-8601 `timestamp`, lowercase `hex`, `range {start,end}`).
@MainActor
final class SessionExportSpec: XCTestCase {

    override func setUp() async throws {
        WireTap.clearAll()
    }

    // MARK: AC-1 — export bundles all three streams

    func test_AC1_exportRoundTripsAllStreams() throws {
        WireTap.network.record(NetworkEntry(method: "GET", url: "https://a", durationMs: 1))
        WireTap.network.record(NetworkEntry(method: "POST", url: "https://b", durationMs: 2))
        WireTap.ble.log(BleEntry(type: .connected, device: "MS2"))
        WireTap.ble.log(BleEntry(type: .disconnected, device: "MS2", error: "x"))
        WireTap.ble.log(BleEntry(type: .notification, data: Data([0x01, 0x02])))
        WireTap.nfc.log(NfcEntry(type: .scanCompleted, detail: "ok"))

        let data = try WireTap.exportSessionData()
        let s = try WireTap.importSession(data)

        XCTAssertEqual(s.network.count, 2)
        XCTAssertEqual(s.ble.count, 3)
        XCTAssertEqual(s.nfc.count, 1)
        XCTAssertNotNil(s.range)
        XCTAssertTrue(s.network.contains { $0.url == "https://b" && $0.method == "POST" })
        XCTAssertTrue(s.ble.contains { $0.type == "disconnected" })
        XCTAssertEqual(s.ble.first(where: { $0.type == "notification" })?.hex, "0102")
    }

    // MARK: AC-2 — unified timeline is deterministically time-ordered

    func test_AC2_timelineIsDeterministicallyOrdered() throws {
        let t0 = Date(timeIntervalSince1970: 1_000)
        let t1 = Date(timeIntervalSince1970: 1_001)
        WireTap.nfc.log(NfcEntry(date: t1, type: .scanStarted))
        WireTap.network.record(NetworkEntry(date: t0, method: "GET", url: "https://x", durationMs: 1))
        WireTap.ble.log(BleEntry(date: t0, type: .connected)) // same time as the network entry

        let items = WireTap.timeline()
        let times = items.map(\.timestamp)
        XCTAssertEqual(times, times.sorted(), "ascending by timestamp")

        // Tie at t0 is broken by kind: ble < network alphabetically.
        XCTAssertEqual(Array(items.prefix(2)).map { $0.kind.rawValue }, ["ble", "network"])
        XCTAssertEqual(items.last?.kind.rawValue, "nfc") // t1 is latest
    }

    // MARK: AC-3 — empty capture exports a valid, empty session

    func test_AC3_emptySessionIsValid() throws {
        let s = WireTap.makeSession()
        XCTAssertTrue(s.network.isEmpty && s.ble.isEmpty && s.nfc.isEmpty)
        XCTAssertNil(s.range)
    }

    // MARK: AC-4 — redaction holds through export

    func test_AC4_exportStaysRedacted() throws {
        WireTap.network.record(NetworkEntry(
            method: "POST",
            url: "https://x",
            requestHeaders: ["Authorization": "Bearer super-secret"],
            durationMs: 1
        ))
        let data = try WireTap.exportSessionData()
        let str = String(data: data, encoding: .utf8)!
        XCTAssertFalse(str.contains("super-secret"))
        XCTAssertTrue(str.contains("[redacted]"))
    }

    // MARK: AC-5 — import is read-only

    func test_AC5_importDoesNotMutateLiveStores() throws {
        WireTap.network.record(NetworkEntry(method: "GET", url: "https://live", durationMs: 1))
        WireTap.ble.log(BleEntry(type: .connected))
        let snapshot = try WireTap.exportSessionData()

        let before = WireTap.network.entries.count
        _ = try WireTap.importSession(snapshot)

        XCTAssertEqual(WireTap.network.entries.count, before)
        XCTAssertEqual(WireTap.network.entries.first?.url, "https://live")
    }

    // MARK: AC-6 — schema-version handling

    func test_AC6_rejectsUnsupportedSchema() throws {
        let future = #"""
        {"schemaVersion":99,"exportedAt":"2026-01-01T00:00:00.000Z","app":{"bundleId":"x","version":"1"},"environment":{"os":"iOS","osVersion":"17"},"range":null,"network":[],"ble":[],"nfc":[]}
        """#.data(using: .utf8)!

        XCTAssertThrowsError(try WireTap.importSession(future)) { error in
            guard case WireTapSessionError.unsupportedSchema(let version) = error else {
                return XCTFail("expected unsupportedSchema, got \(error)")
            }
            XCTAssertEqual(version, 99)
        }
    }

    // MARK: AC-7 — metadata is captured

    func test_AC7_metadataPopulated() throws {
        let s = WireTap.makeSession()
        XCTAssertFalse(s.app.bundleId.isEmpty)
        XCTAssertFalse(s.app.version.isEmpty)
        XCTAssertFalse(s.environment.osVersion.isEmpty)
    }
}
