import XCTest
@testable import WireTapCore

/// TRACER-008 — Session Diff.
/// Each test maps 1:1 to an acceptance criterion in `doc/specs/TRACER-008-diff.md`.
@MainActor
final class SessionDiffSpec: XCTestCase {

    override func setUp() async throws {
        WireTap.clearAll()
        WireTap.ble.clearDecoders()
    }

    private func keys(_ sigs: [EventSignature]) -> [String] { sigs.map(\.key) }

    // AC-1 — identical sessions → no differences
    func test_AC1_identical() {
        WireTap.ble.log(BleEntry(type: .connected, device: "MS2"))
        WireTap.ble.log(BleEntry(type: .authSuccess, device: "MS2"))
        let a = WireTap.makeSession()
        let b = WireTap.makeSession()

        let d = WireTap.diff(a, b)
        XCTAssertTrue(d.onlyInA.isEmpty)
        XCTAssertTrue(d.onlyInB.isEmpty)
        XCTAssertTrue(keys(d.common).contains("ble:authSuccess"))
    }

    // AC-2 — divergent BLE outcome
    func test_AC2_bleOutcome() {
        WireTap.ble.log(BleEntry(type: .connected, device: "MS2"))
        WireTap.ble.log(BleEntry(type: .authSuccess, device: "MS2"))
        let working = WireTap.makeSession()

        WireTap.clearAll()
        WireTap.ble.log(BleEntry(type: .connected, device: "MS2"))
        WireTap.ble.log(BleEntry(type: .authFailed, device: "MS2", error: "stale"))
        let failing = WireTap.makeSession()

        let d = WireTap.diff(working, failing)
        XCTAssertTrue(keys(d.onlyInA).contains("ble:authSuccess"))
        XCTAssertTrue(keys(d.onlyInB).contains("ble:authFailed"))
    }

    // AC-3 — network status class change
    func test_AC3_networkStatusClass() {
        WireTap.network.record(NetworkEntry(method: "POST", url: "https://api/s", statusCode: 200, durationMs: 1))
        let a = WireTap.makeSession()

        WireTap.clearAll()
        WireTap.network.record(NetworkEntry(method: "POST", url: "https://api/s", statusCode: 401, durationMs: 1))
        let b = WireTap.makeSession()

        let d = WireTap.diff(a, b)
        XCTAssertTrue(keys(d.onlyInA).contains { $0.contains("2xx") })
        XCTAssertTrue(keys(d.onlyInB).contains { $0.contains("4xx") })
    }

    // AC-4 — count-aware
    func test_AC4_countAware() {
        WireTap.ble.log(BleEntry(type: .connecting, device: "MS2"))
        let a = WireTap.makeSession()

        WireTap.clearAll()
        WireTap.ble.log(BleEntry(type: .connecting, device: "MS2"))
        WireTap.ble.log(BleEntry(type: .connecting, device: "MS2"))
        WireTap.ble.log(BleEntry(type: .connecting, device: "MS2"))
        let b = WireTap.makeSession()

        let d = WireTap.diff(a, b)
        XCTAssertEqual(keys(d.onlyInB).filter { $0 == "ble:connecting" }.count, 2)
    }

    // AC-5 — common events
    func test_AC5_common() {
        WireTap.ble.log(BleEntry(type: .connected, device: "MS2"))
        let a = WireTap.makeSession()
        WireTap.clearAll()
        WireTap.ble.log(BleEntry(type: .connected, device: "MS2"))
        WireTap.ble.log(BleEntry(type: .disconnected, device: "MS2"))
        let b = WireTap.makeSession()

        let d = WireTap.diff(a, b)
        XCTAssertTrue(keys(d.common).contains("ble:connected"))
        XCTAssertTrue(keys(d.onlyInB).contains("ble:disconnected"))
    }
}
