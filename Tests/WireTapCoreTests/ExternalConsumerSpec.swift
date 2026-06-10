import XCTest
import WireTapCore   // deliberately NOT @testable — this file compiles against the
                     // public API only, simulating an external release consumer (MS2).

/// TRACER-013 — validates that the documented consumer integration (spec §5.5)
/// actually compiles and works for an app that imports WireTapCore without
/// access to internal symbols. If this file compiles, the public surface is real.
@MainActor
final class ExternalConsumerSpec: XCTestCase {

    private let uuid = "C0DEC0DE-1003-4B52-A3F1-9F49C1B6D801"

    /// The full integration flow from the spec, verbatim shape.
    func test_specUsageCompilesAndRuns() throws {
        // 1. Construct metadata from public initializers (what MS2 does in release)
        let app = AppInfo(bundleId: "co.hazesoft.ms2", name: "MS2", version: "3.2.0", build: "418")
        let env = EnvInfo.current()

        // 2. Build the report
        let report = WireTapReport(app: app, environment: env, privacy: .standard)

        // 3. Register decoders through the protocol, exactly like a decoder package would
        let registry: any BleDecoderRegistry = report
        registry.registerDecoder(forCharacteristic: uuid) { data in
            ["frame": "\(data.count)B"]
        }

        // 4. Feed events using public BleEntry / NfcEntry initializers
        //    (explicit dates so the sorted output order is deterministic)
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)
        report.add(ble: BleEntry(date: t0, type: .connected, device: "MS2-A1B2"))
        report.add(ble: BleEntry(date: t0.addingTimeInterval(1), type: .notification, uuid: uuid,
                                 device: "MS2-A1B2", data: Data([0x01, 0x02])))
        report.add(ble: BleEntry(date: t0.addingTimeInterval(2), type: .disconnected,
                                 device: "MS2-A1B2", error: "timeout"))
        report.add(nfc: NfcEntry(date: t0.addingTimeInterval(3), type: .scanCompleted,
                                 descriptor: "application/vnd.ms2"))

        // 5. Export both shapes
        let data = try report.exportData()
        let text = report.exportForLLM()

        // 6. The emitted JSON is a valid .wiretapsession the toolchain can re-import
        let session = try WireTap.importSession(data)
        XCTAssertEqual(session.schemaVersion, 1)
        XCTAssertTrue(session.network.isEmpty)
        XCTAssertEqual(session.ble.count, 3)
        XCTAssertEqual(session.nfc.count, 1)
        XCTAssertEqual(session.ble[0].device, "***A1B2")          // anonymized
        XCTAssertEqual(session.ble[1].decoded?["frame"], "2B")    // decoder ran
        XCTAssertFalse(text.isEmpty)
    }

    /// AppInfo.current() / EnvInfo.current() are reachable publicly (release convenience).
    func test_metadataConveniencesArePublic() {
        let app = AppInfo.current()
        let env = EnvInfo.current()
        XCTAssertFalse(app.bundleId.isEmpty)
        XCTAssertFalse(env.os.isEmpty)
    }

    /// LLM export options are constructible and configurable publicly.
    func test_llmOptionsPublic() {
        var options = LLMExportOptions()
        options.format = .jsonl
        options.maxEntriesPerStream = 50
        let report = WireTapReport(app: AppInfo(bundleId: "x", version: "1"))
        report.add(ble: BleEntry(type: .connected, device: "DEV-99"))
        XCTAssertFalse(report.exportForLLM(options).isEmpty)
    }
}
