import XCTest
@testable import WireTapCore

/// TRACER-006 — Connection Lifecycle Timeline.
/// Each test maps 1:1 to an acceptance criterion in `doc/specs/TRACER-006-lifecycle.md`.
@MainActor
final class ConnectionLifecycleSpec: XCTestCase {

    override func setUp() async throws {
        WireTap.clearAll()
        WireTap.ble.clearDecoders()
    }

    private func at(_ t: TimeInterval) -> Date { Date(timeIntervalSince1970: t) }

    // AC-1 — happy path → streaming
    func test_AC1_happyPathStreaming() {
        WireTap.ble.log(BleEntry(date: at(1), type: .connecting, device: "MS2"))
        WireTap.ble.log(BleEntry(date: at(2), type: .connected, device: "MS2"))
        WireTap.ble.log(BleEntry(date: at(3), type: .serviceDiscovered, device: "MS2"))
        WireTap.ble.log(BleEntry(date: at(4), type: .pairingSuccess, device: "MS2"))
        WireTap.ble.log(BleEntry(date: at(5), type: .authSuccess, device: "MS2"))
        WireTap.ble.log(BleEntry(date: at(6), type: .notification, uuid: "x"))

        let attempts = WireTap.ble.connectionAttempts()
        XCTAssertEqual(attempts.count, 1)
        XCTAssertEqual(attempts.first?.outcome, .streaming)
        let phases = attempts.first?.steps.map(\.phase) ?? []
        XCTAssertEqual(phases, [.connecting, .connected, .services, .paired, .authed, .streaming])
    }

    // AC-2 — auth failure → failed(auth)
    func test_AC2_authFailure() {
        WireTap.ble.log(BleEntry(date: at(1), type: .connecting, device: "MS2"))
        WireTap.ble.log(BleEntry(date: at(2), type: .connected, device: "MS2"))
        WireTap.ble.log(BleEntry(date: at(3), type: .authStarted, device: "MS2"))
        WireTap.ble.log(BleEntry(date: at(4), type: .authFailed, device: "MS2", error: "stale cert"))
        WireTap.ble.log(BleEntry(date: at(5), type: .disconnected, device: "MS2", error: "drop"))

        let attempts = WireTap.ble.connectionAttempts()
        XCTAssertEqual(attempts.count, 1)
        XCTAssertEqual(attempts.first?.outcome, .failed(phase: .authFailed, reason: "stale cert"))
    }

    // AC-3 — multiple attempts split
    func test_AC3_multipleAttempts() {
        WireTap.ble.log(BleEntry(date: at(1), type: .connecting, device: "MS2"))
        WireTap.ble.log(BleEntry(date: at(2), type: .connected, device: "MS2"))
        WireTap.ble.log(BleEntry(date: at(3), type: .disconnected, device: "MS2", error: "lost"))
        WireTap.ble.log(BleEntry(date: at(4), type: .connecting, device: "MS2"))
        WireTap.ble.log(BleEntry(date: at(5), type: .connected, device: "MS2"))
        WireTap.ble.log(BleEntry(date: at(6), type: .notification, uuid: "x"))

        let attempts = WireTap.ble.connectionAttempts()
        XCTAssertEqual(attempts.count, 2)
        XCTAssertEqual(attempts.first?.outcome, .disconnected(reason: "lost"))
        XCTAssertEqual(attempts.last?.outcome, .streaming)
    }

    // AC-4 — open attempt → inProgress
    func test_AC4_inProgress() {
        WireTap.ble.log(BleEntry(date: at(1), type: .connecting, device: "MS2"))
        WireTap.ble.log(BleEntry(date: at(2), type: .connected, device: "MS2"))

        let attempt = WireTap.ble.connectionAttempts().first
        XCTAssertEqual(attempt?.outcome, .inProgress)
        XCTAssertNil(attempt?.end)
        XCTAssertNil(attempt?.duration)
    }

    // AC-5 — duration computed
    func test_AC5_duration() throws {
        WireTap.ble.log(BleEntry(date: at(10), type: .connecting, device: "MS2"))
        WireTap.ble.log(BleEntry(date: at(13), type: .disconnected, device: "MS2"))

        let duration = try XCTUnwrap(WireTap.ble.connectionAttempts().first?.duration)
        XCTAssertEqual(duration, 3, accuracy: 0.001)
    }
}
