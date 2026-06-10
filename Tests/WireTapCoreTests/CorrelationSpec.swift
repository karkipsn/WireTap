import XCTest
@testable import WireTapCore

/// TRACER-007 — Cross-Radio Correlation.
/// Each test maps 1:1 to an acceptance criterion in `doc/specs/TRACER-007-correlation.md`.
@MainActor
final class CorrelationSpec: XCTestCase {

    override func setUp() async throws {
        WireTap.clearAll()
        WireTap.ble.clearDecoders()
    }

    private func at(_ t: TimeInterval) -> Date { Date(timeIntervalSince1970: t) }

    // AC-1 — gap clustering splits episodes
    func test_AC1_gapClustering() {
        WireTap.nfc.log(NfcEntry(date: at(0), type: .scanStarted))
        WireTap.ble.log(BleEntry(date: at(1), type: .connecting))
        WireTap.ble.log(BleEntry(date: at(2), type: .connected))
        WireTap.ble.log(BleEntry(date: at(200), type: .connecting))   // > 60s gap → new episode
        WireTap.ble.log(BleEntry(date: at(201), type: .connected))

        let episodes = WireTap.correlatedEpisodes(maxGap: 60)
        XCTAssertEqual(episodes.count, 2)
        XCTAssertEqual(episodes.first?.items.count, 3)
        XCTAssertEqual(episodes.last?.items.count, 2)
    }

    // AC-2 — trigger classified from first event
    func test_AC2_triggerClassification() {
        WireTap.nfc.log(NfcEntry(date: at(0), type: .scanStarted))
        WireTap.ble.log(BleEntry(date: at(1), type: .connected))
        // second episode begins with BLE
        WireTap.ble.log(BleEntry(date: at(500), type: .connecting))

        let episodes = WireTap.correlatedEpisodes(maxGap: 60)
        XCTAssertEqual(episodes.first?.trigger, .nfcTap)
        XCTAssertEqual(episodes.last?.trigger, .bleConnect)
    }

    // AC-3 — per-stream counts
    func test_AC3_counts() {
        WireTap.nfc.log(NfcEntry(date: at(0), type: .scanCompleted))
        WireTap.ble.log(BleEntry(date: at(1), type: .connecting))
        WireTap.ble.log(BleEntry(date: at(2), type: .connected))
        WireTap.network.record(NetworkEntry(date: at(3), method: "POST", url: "https://x", statusCode: 200, durationMs: 1))

        let e = WireTap.correlatedEpisodes(maxGap: 60).first
        XCTAssertEqual(e?.nfcCount, 1)
        XCTAssertEqual(e?.bleCount, 2)
        XCTAssertEqual(e?.networkCount, 1)
        XCTAssertEqual(e?.items.count, 4)
    }

    // AC-4 — items ordered ascending, span streams
    func test_AC4_ordering() {
        WireTap.network.record(NetworkEntry(date: at(3), method: "GET", url: "https://x", durationMs: 1))
        WireTap.nfc.log(NfcEntry(date: at(0), type: .scanStarted))
        WireTap.ble.log(BleEntry(date: at(1), type: .connected))

        let e = WireTap.correlatedEpisodes(maxGap: 60).first
        let times = e?.items.map(\.timestamp) ?? []
        XCTAssertEqual(times, times.sorted())
        let kinds = Set(e?.items.map { $0.kind } ?? [])
        XCTAssertEqual(kinds, [.network, .ble, .nfc])
    }

    // AC-5 — duration & empty
    func test_AC5_durationAndEmpty() throws {
        XCTAssertTrue(WireTap.correlatedEpisodes().isEmpty)

        WireTap.ble.log(BleEntry(date: at(10), type: .connecting))
        WireTap.ble.log(BleEntry(date: at(14), type: .disconnected))
        let duration = try XCTUnwrap(WireTap.correlatedEpisodes(maxGap: 60).first?.duration)
        XCTAssertEqual(duration, 4, accuracy: 0.001)
    }
}
