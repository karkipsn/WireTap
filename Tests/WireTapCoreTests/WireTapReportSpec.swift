import XCTest
@testable import WireTapCore

/// TRACER-013 — Release-Safe Diagnostic Export.
/// Each test maps 1:1 to an acceptance criterion in
/// `doc/specs/TRACER-013-release-diagnostic-export.md`.
@MainActor
final class WireTapReportSpec: XCTestCase {

    private let uuid = "C0DEC0DE-1003-4B52-A3F1-9F49C1B6D801"

    private func makeApp() -> AppInfo {
        AppInfo(bundleId: "com.test.app", name: "TestApp", version: "1.0", build: nil)
    }

    // AC-2 — network array is always empty
    func test_AC2_networkAlwaysEmpty() throws {
        let report = WireTapReport(app: makeApp())
        report.add(ble: BleEntry(type: .connected, device: "MS2-A1B2"))
        let session = report.build()
        XCTAssertTrue(session.network.isEmpty, "network must always be [] in a production report")
        let data = try report.exportData()
        let decoded = try WireTap.importSession(data)
        XCTAssertTrue(decoded.network.isEmpty)
    }

    // AC-3 — device names anonymized at standard privacy level
    func test_AC3_deviceNameTruncated() {
        let report = WireTapReport(app: makeApp(), privacy: .standard)
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)
        report.add(ble: BleEntry(date: t0, type: .connected, device: "MS2-A1B2"))
        report.add(ble: BleEntry(date: t0.addingTimeInterval(1), type: .connected, device: "John's Headset"))
        report.add(ble: BleEntry(date: t0.addingTimeInterval(2), type: .connected, device: "AB"))  // ≤4 chars — kept as-is
        let session = report.build()
        XCTAssertEqual(session.ble[0].device, "***A1B2")
        XCTAssertEqual(session.ble[1].device, "***dset")
        XCTAssertEqual(session.ble[2].device, "AB")               // short names unchanged
    }

    // AC-3 — anonymization edge cases: unicode, empty, boundary lengths
    func test_AC3_anonymizationEdgeCases() {
        let report = WireTapReport(app: makeApp(), privacy: .standard)
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)
        func at(_ s: TimeInterval) -> Date { t0.addingTimeInterval(s) }
        report.add(ble: BleEntry(date: at(0), type: .connected, device: ""))          // empty
        report.add(ble: BleEntry(date: at(1), type: .connected, device: "Ana"))       // 3 chars
        report.add(ble: BleEntry(date: at(2), type: .connected, device: "Anna"))      // exactly 4
        report.add(ble: BleEntry(date: at(3), type: .connected, device: "Annas"))     // 5 chars
        report.add(ble: BleEntry(date: at(4), type: .connected, device: "日本語デバイス名")) // unicode, 8 chars
        report.add(ble: BleEntry(date: at(5), type: .connected))                      // nil device
        let ble = report.build().ble
        XCTAssertEqual(ble[0].device, "")          // empty kept
        XCTAssertEqual(ble[1].device, "Ana")       // ≤4 kept as-is
        XCTAssertEqual(ble[2].device, "Anna")      // ≤4 kept as-is
        XCTAssertEqual(ble[3].device, "***nnas")   // >4 truncated
        XCTAssertEqual(ble[4].device, "***バイス名",
                       "unicode suffix must be Character-correct, no broken scalars")
        XCTAssertNil(ble[5].device)                // nil stays nil
    }

    // AC-3 (verbose) — full names kept when privacy == .verbose
    func test_AC3_verboseKeepsFullName() {
        let report = WireTapReport(app: makeApp(), privacy: .verbose)
        report.add(ble: BleEntry(type: .connected, device: "MS2-A1B2"))
        XCTAssertEqual(report.build().ble.first?.device, "MS2-A1B2")
    }

    // AC-3 — characteristic UUIDs are never truncated
    func test_AC3_characteristicUUIDKeptInFull() {
        let report = WireTapReport(app: makeApp(), privacy: .standard)
        report.add(ble: BleEntry(type: .notification, uuid: uuid, device: "MS2-A1B2"))
        let record = report.build().ble.first!
        XCTAssertEqual(record.uuid, uuid)   // UUID unchanged
        XCTAssertEqual(record.device, "***A1B2")
    }

    // AC-4 — registered decoder runs during build()
    func test_AC4_decoderRunsOnBuild() {
        let report = WireTapReport(app: makeApp())
        report.registerDecoder(forCharacteristic: uuid) { data in
            ["len": "\(data.count)", "first": String(format: "0x%02X", data.first ?? 0)]
        }
        report.add(ble: BleEntry(type: .notification, uuid: uuid, data: Data([0x0a, 0xff])))
        let record = report.build().ble.first!
        XCTAssertEqual(record.decoded?["len"], "2")
        XCTAssertEqual(record.decoded?["first"], "0x0A")
    }

    // AC-4 — decoder UUID matching is case-insensitive
    func test_AC4_decoderCaseInsensitive() {
        let report = WireTapReport(app: makeApp())
        report.registerDecoder(forCharacteristic: uuid.lowercased()) { _ in ["ok": "1"] }
        report.add(ble: BleEntry(type: .notification, uuid: uuid.uppercased(), data: Data([0x01])))
        XCTAssertEqual(report.build().ble.first?.decoded?["ok"], "1")
    }

    // AC-5 — format parity: WireTapReport output is byte-compatible with debug makeSession()
    func test_AC5_formatParityWithDebugSession() async throws {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let bleEntry = BleEntry(id: UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!,
                                date: date, type: .connected, device: "MS2-A1B2")
        let nfcEntry = NfcEntry(id: UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!,
                                date: date.addingTimeInterval(1), type: .scanCompleted, descriptor: "test")

        // Build via WireTapReport (release path)
        let report = WireTapReport(
            app: AppInfo(bundleId: Bundle.main.bundleIdentifier ?? "com.test", name: "TestApp",
                         version: "1.0", build: nil),
            environment: EnvInfo.current(),
            privacy: .verbose   // full names so we can compare directly
        )
        report.add(ble: bleEntry)
        report.add(nfc: nfcEntry)
        let reportSession = report.build()

        // Build equivalent via debug path
        WireTap.clearAll()
        WireTap.ble.log(bleEntry)
        WireTap.nfc.log(nfcEntry)
        let debugSession = WireTap.makeSession()
        WireTap.clearAll()

        // Same schema version
        XCTAssertEqual(reportSession.schemaVersion, debugSession.schemaVersion)
        // Same BLE record shape
        XCTAssertEqual(reportSession.ble.count, debugSession.ble.count)
        let rb = reportSession.ble.first!
        let db = debugSession.ble.first!
        XCTAssertEqual(rb.type, db.type)
        XCTAssertEqual(rb.device, db.device)
        XCTAssertEqual(rb.timestamp, db.timestamp)
        // Same NFC record shape
        XCTAssertEqual(reportSession.nfc.count, debugSession.nfc.count)
        XCTAssertEqual(reportSession.nfc.first?.type, debugSession.nfc.first?.type)
        // Network always empty in report
        XCTAssertTrue(reportSession.network.isEmpty)
    }

    // AC-6 — no files written to disk
    func test_AC6_noFilesWritten() throws {
        let before = try FileManager.default.contentsOfDirectory(
            atPath: NSTemporaryDirectory()
        ).count
        let report = WireTapReport(app: makeApp())
        report.add(ble: BleEntry(type: .connected, device: "MS2-A1B2"))
        _ = try report.exportData()
        let after = try FileManager.default.contentsOfDirectory(
            atPath: NSTemporaryDirectory()
        ).count
        XCTAssertEqual(before, after, "exportData() must not write any files to disk")
    }

    // AC-6 — build() is non-destructive (callable multiple times)
    func test_AC6_buildIsNonDestructive() {
        let report = WireTapReport(app: makeApp())
        report.add(ble: BleEntry(type: .connected, device: "MS2"))
        let s1 = report.build()
        report.add(ble: BleEntry(type: .disconnected, device: "MS2"))
        let s2 = report.build()
        XCTAssertEqual(s1.ble.count, 1)
        XCTAssertEqual(s2.ble.count, 2)
    }

    // BleDecoderRegistry protocol: WireTapReport conforms
    func test_bleDecoderRegistryConformance() {
        let report = WireTapReport(app: makeApp())
        let registry: any BleDecoderRegistry = report
        registry.registerDecoder(forCharacteristic: uuid) { _ in ["x": "1"] }
        report.add(ble: BleEntry(type: .notification, uuid: uuid, data: Data([0x01])))
        XCTAssertEqual(report.build().ble.first?.decoded?["x"], "1")
    }

    // WireTapReport.exportForLLM() returns non-empty text when there are events
    func test_exportForLLMProducesOutput() {
        let report = WireTapReport(app: makeApp())
        report.add(ble: BleEntry(type: .connected, device: "MS2-A1B2"))
        let text = report.exportForLLM()
        XCTAssertFalse(text.isEmpty)
        XCTAssertTrue(text.contains("ble"), "LLM export should mention ble section")
    }
}
