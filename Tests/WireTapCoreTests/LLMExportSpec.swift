import XCTest
@testable import WireTapCore

/// TRACER-003 — LLM-Optimized Export.
///
/// Each test maps 1:1 to an acceptance criterion in
/// `doc/specs/TRACER-003-llm-export.md`.
@MainActor
final class LLMExportSpec: XCTestCase {

    override func setUp() async throws {
        WireTap.clearAll()
    }

    // MARK: AC-1 — deterministic output

    func test_AC1_deterministic() throws {
        WireTap.network.record(NetworkEntry(method: "GET", url: "https://a", durationMs: 1))
        WireTap.ble.log(BleEntry(type: .connected, device: "MS2"))
        let session = WireTap.makeSession()

        let a = WireTap.exportForLLM(session)
        let b = WireTap.exportForLLM(session)
        XCTAssertEqual(a, b)
    }

    // MARK: AC-2 — payload truncation is marked

    func test_AC2_payloadTruncationMarked() throws {
        let big = Data(repeating: 0xAB, count: 300) // 300 bytes
        WireTap.ble.log(BleEntry(type: .notification, data: big))

        let out = WireTap.exportForLLM() // default maxPayloadBytes = 256
        XCTAssertTrue(out.contains("…+44 more bytes"), "truncation marker with remaining-byte count")
        XCTAssertFalse(out.contains(String(repeating: "ab", count: 300)), "full payload must not appear")
    }

    // MARK: AC-3 — entry cap is marked

    func test_AC3_entryCapMarked() throws {
        for i in 1...500 {
            WireTap.network.record(NetworkEntry(method: "GET", url: "https://x/\(i)", durationMs: i))
        }
        var opts = LLMExportOptions(); opts.maxEntriesPerStream = 200
        let out = WireTap.exportForLLM(opts)

        XCTAssertTrue(out.contains("showing newest 200 of 500"))
        let netLines = out.split(separator: "\n").filter { $0.contains(" net ") }
        XCTAssertEqual(netLines.count, 200)
    }

    // MARK: AC-4 — schema preamble present & toggleable

    func test_AC4_schemaPreambleToggle() throws {
        WireTap.ble.log(BleEntry(type: .connected))
        var on = LLMExportOptions(); on.includeSchemaPreamble = true
        var off = LLMExportOptions(); off.includeSchemaPreamble = false

        XCTAssertTrue(WireTap.exportForLLM(on).contains("Schema:"))
        XCTAssertFalse(WireTap.exportForLLM(off).contains("Schema:"))
    }

    // MARK: AC-5 — redaction holds in both formats

    func test_AC5_redactedInBothFormats() throws {
        WireTap.network.record(NetworkEntry(
            method: "POST",
            url: "https://x",
            requestHeaders: ["Authorization": "Bearer top-secret"],
            durationMs: 1
        ))
        var md = LLMExportOptions(); md.format = .markdown
        var jl = LLMExportOptions(); jl.format = .jsonl

        XCTAssertFalse(WireTap.exportForLLM(md).contains("top-secret"))
        XCTAssertFalse(WireTap.exportForLLM(jl).contains("top-secret"))
    }

    // MARK: AC-6 — stream selection respected

    func test_AC6_streamSelection() throws {
        WireTap.network.record(NetworkEntry(method: "GET", url: "https://x", durationMs: 1))
        WireTap.ble.log(BleEntry(type: .connected))
        WireTap.nfc.log(NfcEntry(type: .scanStarted))

        var opts = LLMExportOptions(); opts.include = [.ble]
        let out = WireTap.exportForLLM(opts)

        XCTAssertTrue(out.contains(" ble "))
        XCTAssertFalse(out.contains(" net "))
        XCTAssertFalse(out.contains(" nfc "))
    }

    // MARK: AC-7 — JSONL is valid & parseable

    func test_AC7_jsonlEachLineParses() throws {
        WireTap.network.record(NetworkEntry(method: "GET", url: "https://x", durationMs: 1))
        WireTap.ble.log(BleEntry(type: .connected, device: "MS2"))
        WireTap.nfc.log(NfcEntry(type: .scanStarted))

        var opts = LLMExportOptions(); opts.format = .jsonl
        let out = WireTap.exportForLLM(opts)

        let lines = out.split(separator: "\n", omittingEmptySubsequences: true)
        XCTAssertGreaterThan(lines.count, 1)
        for line in lines {
            XCTAssertNoThrow(
                try JSONSerialization.jsonObject(with: Data(line.utf8)),
                "every line must be valid JSON: \(line)"
            )
        }
    }

    // MARK: AC-8 — empty snapshot

    func test_AC8_emptySnapshot() throws {
        let out = WireTap.exportForLLM()
        XCTAssertTrue(out.contains("no events"), "should explicitly note that no events were captured")
    }

    // MARK: AC-9 — filter by BLE event type

    func test_AC9_bleTypeFilter() throws {
        WireTap.ble.log(BleEntry(type: .connected, device: "AAA"))
        WireTap.ble.log(BleEntry(type: .disconnected, device: "BBB"))
        WireTap.ble.log(BleEntry(type: .notification, device: "CCC"))

        var opts = LLMExportOptions(); opts.bleTypes = [.disconnected]
        let out = WireTap.exportForLLM(opts)

        XCTAssertTrue(out.contains("device=BBB"))
        XCTAssertFalse(out.contains("device=AAA"))
        XCTAssertFalse(out.contains("device=CCC"))
    }

    // MARK: AC-10 — filter by search text

    func test_AC10_searchFilter() throws {
        WireTap.ble.log(BleEntry(type: .connected, device: "keep-me"))
        WireTap.ble.log(BleEntry(type: .connected, device: "drop-me"))

        var opts = LLMExportOptions(); opts.searchText = "keep-me"
        let out = WireTap.exportForLLM(opts)

        XCTAssertTrue(out.contains("keep-me"))
        XCTAssertFalse(out.contains("drop-me"))
    }

    // MARK: AC-11 — request/response bodies shown for FAILED network calls only

    func test_AC11_failureBodiesIncludedSuccessOmitted() throws {
        WireTap.network.record(NetworkEntry(
            method: "POST", url: "https://api/sessions",
            requestBody: #"{"deviceId":"MS2"}"#,
            statusCode: 401,
            responseBody: #"{"error":"device not authenticated"}"#,
            durationMs: 12
        ))
        WireTap.network.record(NetworkEntry(
            method: "GET", url: "https://api/ok",
            statusCode: 200,
            responseBody: #"{"body":"omit-on-success"}"#,
            durationMs: 5
        ))
        let out = WireTap.exportForLLM()

        XCTAssertTrue(out.contains(#"resp={"error":"device not authenticated"}"#))
        XCTAssertTrue(out.contains(#"req={"deviceId":"MS2"}"#))
        XCTAssertFalse(out.contains("omit-on-success"), "successful responses should not dump bodies")
    }

    // MARK: AC-12 — long bodies are truncated with a marker

    func test_AC12_longBodyTruncated() throws {
        let big = String(repeating: "x", count: 400)
        WireTap.network.record(NetworkEntry(
            method: "POST", url: "https://api/x", statusCode: 500, responseBody: big, durationMs: 1
        ))
        var opts = LLMExportOptions(); opts.maxBodyChars = 256
        let out = WireTap.exportForLLM(opts)

        XCTAssertTrue(out.contains("…+144 more chars"))           // 400 - 256
        XCTAssertFalse(out.contains(String(repeating: "x", count: 400)))
    }
}
