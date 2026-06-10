import XCTest
@testable import WireTapCore

/// TRACER-010 — Configurable Redaction Rules.
/// Each test maps 1:1 to an acceptance criterion in `doc/specs/TRACER-010-redaction.md`.
@MainActor
final class RedactionSpec: XCTestCase {

    override func setUp() async throws {
        WireTap.clearAll()
        WireTap.redaction = .default
    }

    override func tearDown() async throws {
        WireTap.redaction = .default
    }

    // AC-1 — default redacts sensitive headers
    func test_AC1_defaultHeaders() {
        let e = NetworkEntry(
            method: "GET", url: "https://x",
            requestHeaders: ["Authorization": "Bearer secret-abc", "Cookie": "sid=xyz", "Accept": "json"],
            durationMs: 1
        )
        let r = WireTapRedaction.redacted(e, config: WireTap.redaction)
        XCTAssertEqual(r.requestHeaders["Authorization"], "[redacted]")
        XCTAssertEqual(r.requestHeaders["Cookie"], "[redacted]")
        XCTAssertEqual(r.requestHeaders["Accept"], "json")
    }

    // AC-2 — default redacts sensitive body fields in request + response
    func test_AC2_bodyFields() {
        let e = NetworkEntry(
            method: "POST", url: "https://x",
            requestBody: #"{"token":"abc","user":"bob"}"#,
            statusCode: 200,
            responseBody: #"{"access_token":"def","ok":true}"#,
            durationMs: 1
        )
        let r = WireTapRedaction.redacted(e, config: WireTap.redaction)
        XCTAssertEqual(r.requestBody, #"{"token":"[redacted]","user":"bob"}"#)
        XCTAssertEqual(r.responseBody, #"{"access_token":"[redacted]","ok":true}"#)
    }

    // AC-3 — custom rules extend defaults
    func test_AC3_customRules() {
        var cfg = WireTapRedactionConfig.default
        cfg.redactedHeaders.insert("x-trace")
        cfg.redactedBodyKeys.append("pin")
        WireTap.redaction = cfg

        let e = NetworkEntry(
            method: "POST", url: "https://x",
            requestHeaders: ["X-Trace": "t-123", "X-Keep": "ok"],
            requestBody: #"{"pin":"0000","name":"bob"}"#,
            durationMs: 1
        )
        let r = WireTapRedaction.redacted(e, config: WireTap.redaction)
        XCTAssertEqual(r.requestHeaders["X-Trace"], "[redacted]")
        XCTAssertEqual(r.requestHeaders["X-Keep"], "ok")
        XCTAssertEqual(r.requestBody, #"{"pin":"[redacted]","name":"bob"}"#)
    }

    // AC-4 — redaction reaches the LLM export bodies
    func test_AC4_llmExportRedactsBody() {
        WireTap.network.record(NetworkEntry(
            method: "POST", url: "https://api/login",
            statusCode: 401,
            responseBody: #"{"token":"leak","error":"bad"}"#,
            durationMs: 1
        ))
        let out = WireTap.exportForLLM()
        XCTAssertFalse(out.contains("leak"))
        XCTAssertTrue(out.contains(#""token":"[redacted]""#))
    }

    // AC-5 — non-sensitive content unchanged (determinism / golden safety)
    func test_AC5_nonSensitiveUnchanged() {
        let body = #"{"error":"device not authenticated"}"#
        let e = NetworkEntry(method: "POST", url: "https://x", statusCode: 401, responseBody: body, durationMs: 1)
        let r = WireTapRedaction.redacted(e, config: WireTap.redaction)
        XCTAssertEqual(r.responseBody, body)
    }

    // AC-6 — redaction precedes disk persistence
    func test_AC6_redactedBeforeDisk() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("redact-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let net = NetworkStore()
        net.enableDiskPersistence(fileURL: tmp.appendingPathComponent("network.jsonl"), fileCap: 100)
        net.record(NetworkEntry(method: "POST", url: "https://x", requestBody: #"{"password":"hunter2"}"#, durationMs: 1))
        net.flushPersistenceForTesting()

        let raw = try String(contentsOf: tmp.appendingPathComponent("network.jsonl"), encoding: .utf8)
        XCTAssertFalse(raw.contains("hunter2"))
        XCTAssertTrue(raw.contains("[redacted]"))
    }
}
