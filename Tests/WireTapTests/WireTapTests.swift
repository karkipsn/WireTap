import XCTest
@testable import WireTap

@MainActor
final class WireTapTests: XCTestCase {

    override func setUp() async throws {
        WireTap.clearAll()
    }

    // MARK: Network

    func testNetworkRecord() {
        let entry = NetworkEntry(method: "GET", url: "https://example.com", durationMs: 42)
        WireTap.network.record(entry)
        XCTAssertEqual(WireTap.network.entries.count, 1)
        XCTAssertEqual(WireTap.network.entries.first?.method, "GET")
    }

    func testNetworkMaxEntries() {
        WireTap.network.maxEntries = 3
        for i in 1...5 {
            WireTap.network.record(NetworkEntry(method: "GET", url: "https://example.com/\(i)", durationMs: i))
        }
        XCTAssertEqual(WireTap.network.entries.count, 3)
        XCTAssertEqual(WireTap.network.entries.first?.url, "https://example.com/5")
    }

    func testNetworkCurlCommand() {
        let entry = NetworkEntry(
            method: "POST",
            url: "https://api.example.com/sessions",
            requestHeaders: ["Authorization": "Bearer token", "Content-Type": "application/json"],
            requestBody: #"{"key":"value"}"#,
            durationMs: 100
        )
        XCTAssertTrue(entry.curlCommand.contains("curl -X POST"))
        XCTAssertTrue(entry.curlCommand.contains("Authorization"))
        XCTAssertTrue(entry.curlCommand.contains("https://api.example.com/sessions"))
    }

    func testNetworkSuccessStatus() {
        let ok = NetworkEntry(method: "GET", url: "", statusCode: 201, durationMs: 0)
        XCTAssertTrue(ok.isSuccess)
        let fail = NetworkEntry(method: "GET", url: "", statusCode: 404, durationMs: 0)
        XCTAssertFalse(fail.isSuccess)
    }

    // MARK: BLE

    func testBleLog() {
        WireTap.ble.log(BleEntry(type: .connected, device: "MS2-001"))
        XCTAssertEqual(WireTap.ble.entries.count, 1)
        XCTAssertEqual(WireTap.ble.entries.first?.type, .connected)
    }

    func testBleHexAndAscii() {
        let data = Data([0x48, 0x65, 0x6C, 0x6C, 0x6F]) // "Hello"
        let entry = BleEntry(type: .notification, data: data)
        XCTAssertEqual(entry.hexString, "48 65 6C 6C 6F")
        XCTAssertEqual(entry.asciiString, "Hello")
    }

    func testBleNonPrintableAscii() {
        let data = Data([0x00, 0x41, 0xFF]) // null, 'A', 0xFF
        let entry = BleEntry(type: .characteristicRead, data: data)
        XCTAssertEqual(entry.asciiString, ".A.")
    }

    // MARK: NFC

    func testNfcLog() {
        WireTap.nfc.log(NfcEntry(type: .scanStarted, detail: "requireOobHandshake: false"))
        XCTAssertEqual(WireTap.nfc.entries.count, 1)
        XCTAssertEqual(WireTap.nfc.entries.first?.type, .scanStarted)
        XCTAssertEqual(WireTap.nfc.entries.first?.detail, "requireOobHandshake: false")
    }

    func testNfcMaxEntries() {
        WireTap.nfc.maxEntries = 3
        for i in 1...5 {
            WireTap.nfc.log(NfcEntry(type: .recordParsed, descriptor: "mime/type/\(i)"))
        }
        XCTAssertEqual(WireTap.nfc.entries.count, 3)
        XCTAssertEqual(WireTap.nfc.entries.first?.descriptor, "mime/type/5")
    }

    func testNfcHexAndAscii() {
        let payload = Data([0x4D, 0x53, 0x32]) // "MS2"
        let entry = NfcEntry(type: .recordParsed, descriptor: "application/vnd.novason.ms2.addr", data: payload)
        XCTAssertEqual(entry.hexString, "4D 53 32")
        XCTAssertEqual(entry.asciiString, "MS2")
    }

    func testNfcNonPrintablePayload() {
        let data = Data([0x00, 0x41, 0xFF])
        let entry = NfcEntry(type: .apduReceived, data: data)
        XCTAssertEqual(entry.asciiString, ".A.")
    }

    func testNfcEventTypeClassification() {
        XCTAssertTrue(NfcEventType.scanFailed.isError)
        XCTAssertFalse(NfcEventType.scanStarted.isError)
        XCTAssertTrue(NfcEventType.scanCompleted.isSuccess)
        XCTAssertTrue(NfcEventType.iosTrustDecoded.isSuccess)
        XCTAssertFalse(NfcEventType.tagDetected.isSuccess)
    }

    func testNfcErrorEntry() {
        let entry = NfcEntry(type: .scanFailed, error: "Connection lost")
        XCTAssertEqual(entry.error, "Connection lost")
        XCTAssertNil(entry.hexString)
        XCTAssertNil(entry.asciiString)
    }

    func testNfcClear() {
        WireTap.nfc.log(NfcEntry(type: .tagDetected, descriptor: "MiFare (NFC-A/B)"))
        WireTap.nfc.log(NfcEntry(type: .scanCompleted))
        XCTAssertEqual(WireTap.nfc.entries.count, 2)
        WireTap.nfc.clear()
        XCTAssertTrue(WireTap.nfc.entries.isEmpty)
    }

    // MARK: ClearAll

    func testClearAll() {
        WireTap.network.record(NetworkEntry(method: "GET", url: "https://x.com", durationMs: 1))
        WireTap.ble.log(BleEntry(type: .info))
        WireTap.nfc.log(NfcEntry(type: .scanCompleted))
        WireTap.clearAll()
        XCTAssertTrue(WireTap.network.entries.isEmpty)
        XCTAssertTrue(WireTap.ble.entries.isEmpty)
        XCTAssertTrue(WireTap.nfc.entries.isEmpty)
    }
}
