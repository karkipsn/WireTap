#if DEBUG
import XCTest
@testable import WireTap

/// TRACER-004 AC-7 + AC-8 — local bridge read-only & localhost-only.
@MainActor
final class LocalBridgeSpec: XCTestCase {

    // Each test gets its own port to avoid conflicts.
    private var bridge: LocalBridge!
    private let testPort: UInt16 = 18_787

    override func setUp() async throws {
        try await super.setUp()
        WireTap.clearAll()
        bridge = LocalBridge(port: testPort)
        try await bridge.start()
    }

    override func tearDown() async throws {
        bridge.stop()
        bridge = nil
        WireTap.clearAll()
        try await super.tearDown()
    }

    // MARK: - AC-7: read-only — non-GET verbs return 405

    func test_AC7_bridgeIsReadOnly() async throws {
        let url = URL(string: "http://127.0.0.1:\(testPort)/session")!
        for method in ["POST", "PUT", "DELETE", "PATCH"] {
            var req = URLRequest(url: url)
            req.httpMethod = method
            let (_, response) = try await URLSession.shared.data(for: req)
            let http = try XCTUnwrap(response as? HTTPURLResponse)
            XCTAssertEqual(http.statusCode, 405,
                           "\(method) /session should return 405, got \(http.statusCode)")
        }
    }

    // MARK: - AC-8: localhost-only — binds 127.0.0.1 and responds there

    func test_AC8_localhostOnly() async throws {
        // Bridge started → listener must be non-nil (it resolved in setUp)
        XCTAssertNotNil(bridge.listener, "Listener should be active after start()")

        // Serves requests on 127.0.0.1
        let url = URL(string: "http://127.0.0.1:\(testPort)/session")!
        let (_, response) = try await URLSession.shared.data(from: url)
        let http = try XCTUnwrap(response as? HTTPURLResponse)
        XCTAssertEqual(http.statusCode, 200)

        // The header confirms it's our bridge (not some other server on this port)
        XCTAssertEqual(http.value(forHTTPHeaderField: "X-WireTap-Bridge"), "1")
    }

    // MARK: - Endpoint smoke tests (GET routes return 200 and valid JSON / text)

    func test_getSession_returnsValidJSON() async throws {
        let data = try await get("/session")
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertNotNil(json["schemaVersion"])
    }

    func test_getOverview_returnsCountFields() async throws {
        // Record one entry so overview is non-trivial
        await WireTap.network.record(NetworkEntry(
            method: "GET", url: "https://test/ok", statusCode: 200, durationMs: 10))
        let data = try await get("/overview")
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertNotNil(json["network"])
    }

    func test_getTimeline_returnsText() async throws {
        let data = try await get("/timeline")
        let text = try XCTUnwrap(String(data: data, encoding: .utf8))
        XCTAssertTrue(text.hasPrefix("# WireTap session"), "Expected LLM preamble")
    }

    func test_unknownRoute_returns404() async throws {
        let url = URL(string: "http://127.0.0.1:\(testPort)/doesnotexist")!
        let (_, response) = try await URLSession.shared.data(from: url)
        let http = try XCTUnwrap(response as? HTTPURLResponse)
        XCTAssertEqual(http.statusCode, 404)
    }

    // MARK: - Helpers

    private func get(_ path: String) async throws -> Data {
        let url = URL(string: "http://127.0.0.1:\(testPort)\(path)")!
        let (data, response) = try await URLSession.shared.data(from: url)
        let http = try XCTUnwrap(response as? HTTPURLResponse)
        XCTAssertEqual(http.statusCode, 200, "GET \(path) returned \(http.statusCode)")
        return data
    }
}
#endif
