import XCTest
@testable import WireTapCore

/// TRACER-005 — Pluggable Protocol Decoders.
/// Each test maps 1:1 to an acceptance criterion in `doc/specs/TRACER-005-decoders.md`.
@MainActor
final class BleDecoderSpec: XCTestCase {

    private let uuid = "C0DEC0DE-1003-4B52-A3F1-9F49C1B6D801"

    override func setUp() async throws {
        WireTap.clearAll()
        WireTap.ble.clearDecoders()
    }

    override func tearDown() async throws {
        WireTap.ble.clearDecoders()
    }

    // AC-1 — registered decoder attaches named fields
    func test_AC1_decoderAttachesFields() {
        WireTap.ble.registerDecoder(forCharacteristic: uuid) { data in
            ["len": "\(data.count)", "first": String(format: "0x%02X", data.first ?? 0)]
        }
        WireTap.ble.log(BleEntry(type: .notification, uuid: uuid, data: Data([0x0a, 0xff])))
        XCTAssertEqual(WireTap.ble.entries.first?.decoded?["len"], "2")
        XCTAssertEqual(WireTap.ble.entries.first?.decoded?["first"], "0x0A")
    }

    // AC-2 — no decoder ⇒ no decoded
    func test_AC2_noDecoderLeavesNil() {
        WireTap.ble.log(BleEntry(type: .notification, uuid: uuid, data: Data([0x01])))
        XCTAssertNil(WireTap.ble.entries.first?.decoded)
    }

    // AC-3 — UUID match is case-insensitive and scoped
    func test_AC3_caseInsensitiveAndScoped() {
        WireTap.ble.registerDecoder(forCharacteristic: uuid.lowercased()) { _ in ["ok": "1"] }
        WireTap.ble.log(BleEntry(type: .notification, uuid: uuid, data: Data([0x01])))          // uppercase
        WireTap.ble.log(BleEntry(type: .notification, uuid: "OTHER-UUID", data: Data([0x01])))
        XCTAssertEqual(WireTap.ble.entries.last?.decoded?["ok"], "1")   // first logged → last in newest-first
        XCTAssertNil(WireTap.ble.entries.first?.decoded)                // OTHER-UUID
    }

    // AC-4 — empty decode result leaves nil
    func test_AC4_emptyResultIsNil() {
        WireTap.ble.registerDecoder(forCharacteristic: uuid) { _ in [:] }
        WireTap.ble.log(BleEntry(type: .notification, uuid: uuid, data: Data([0x01])))
        XCTAssertNil(WireTap.ble.entries.first?.decoded)
    }

    // AC-5 — decoded survives session export round-trip
    func test_AC5_decodedRoundTripsExport() throws {
        WireTap.ble.registerDecoder(forCharacteristic: uuid) { _ in ["a8": "2.1", "status": "ok"] }
        WireTap.ble.log(BleEntry(type: .notification, uuid: uuid, data: Data([0x01])))
        let session = try WireTap.importSession(try WireTap.exportSessionData())
        let rec = session.ble.first { $0.type == "notification" }
        XCTAssertEqual(rec?.decoded?["a8"], "2.1")
        XCTAssertEqual(rec?.decoded?["status"], "ok")
    }

    // AC-6 — decoded appears in LLM export
    func test_AC6_decodedInLLMExport() {
        WireTap.ble.registerDecoder(forCharacteristic: uuid) { _ in ["a8": "2.1"] }
        WireTap.ble.log(BleEntry(type: .notification, uuid: uuid, data: Data([0x01])))
        let out = WireTap.exportForLLM()
        XCTAssertTrue(out.contains("a8=2.1"), "decoded fields should be in the LLM render:\n\(out)")
    }

    // AC-7 — removeDecoder stops decoding
    func test_AC7_removeDecoder() {
        WireTap.ble.registerDecoder(forCharacteristic: uuid) { _ in ["ok": "1"] }
        WireTap.ble.removeDecoder(forCharacteristic: uuid)
        WireTap.ble.log(BleEntry(type: .notification, uuid: uuid, data: Data([0x01])))
        XCTAssertNil(WireTap.ble.entries.first?.decoded)
    }
}
