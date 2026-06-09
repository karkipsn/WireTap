#if DEBUG
import Network
import Foundation

// MARK: - OnceFlag (thread-safe single-fire guard)

/// Wraps a Bool so that NWListener's state handler can fire exactly once across threads.
private final class OnceFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var fired = false

    /// Returns `true` the first time, `false` on every subsequent call.
    func set() -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard !fired else { return false }
        fired = true
        return true
    }
}

// MARK: - LocalBridge (TRACER-004 live mode, AC-7 / AC-8)

/// Minimal read-only HTTP/1.1 server bound exclusively to 127.0.0.1.
/// Serves the current WireTap capture so the `wiretap-mcp` MCP server can query
/// live traffic without a file export step.
///
/// Endpoints (all GET-only; others → 405):
///   GET /session              — full WireTapSession JSON
///   GET /overview             — event counts + error summary
///   GET /timeline             — LLM-rendered text (reuses TRACER-003 renderer)
///   GET /ble?type=&uuid=&device=&limit=  — filtered BLE records
///   GET /network/failures?limit=         — non-2xx / errored network records
///   GET /nfc                  — NFC records
@MainActor
final class LocalBridge {

    let port: UInt16
    private(set) var listener: NWListener?

    // Background queue for NWListener I/O — never the main actor.
    private let ioQueue = DispatchQueue(label: "WireTap.LocalBridge.io", qos: .utility)

    init(port: UInt16) {
        self.port = port
    }

    // MARK: - Lifecycle

    /// Bind the port and resolve when the listener is ready to accept connections.
    func start() async throws {
        let params = NWParameters.tcp
        // AC-8: bind loopback only — never 0.0.0.0 / any interface.
        params.requiredLocalEndpoint = .hostPort(
            host: NWEndpoint.Host("127.0.0.1"),
            port: NWEndpoint.Port(rawValue: port)!
        )
        let l = try NWListener(using: params)

        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            // Box protects against a second state-handler call racing on the ioQueue.
            let once = OnceFlag()
            l.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    if once.set() { cont.resume() }
                case .failed(let err):
                    if once.set() { cont.resume(throwing: err) }
                default:
                    break
                }
            }
            l.newConnectionHandler = { [weak self] conn in
                Task { @MainActor [weak self] in
                    self?.accept(conn)
                }
            }
            l.start(queue: ioQueue)
        }
        listener = l
    }

    func stop() {
        listener?.cancel()
        listener = nil
    }

    // MARK: - Connection handling

    private func accept(_ conn: NWConnection) {
        conn.start(queue: ioQueue)
        conn.receive(minimumIncompleteLength: 1, maximumLength: 8_192) { [weak self] data, _, _, _ in
            let raw = data.flatMap { String(bytes: $0, encoding: .utf8) } ?? ""
            Task { @MainActor [weak self] in
                guard let self else { conn.cancel(); return }
                let response = self.buildResponse(for: raw)
                self.send(response, on: conn)
            }
        }
    }

    @MainActor
    private func buildResponse(for raw: String) -> String {
        let firstLine = raw.split(separator: "\r\n", maxSplits: 1).first.map(String.init) ?? ""
        let parts = firstLine.split(separator: " ").map(String.init)
        guard parts.count >= 2 else {
            return httpResponse(status: 400, body: #"{"error":"bad request"}"#)
        }
        let method = parts[0]
        let fullPath = parts[1]

        // AC-7: read-only — any non-GET verb is rejected with 405.
        guard method == "GET" else {
            return httpResponse(status: 405, body: #"{"error":"method not allowed"}"#,
                                extra: "Allow: GET")
        }

        let (status, body, contentType) = route(fullPath)
        return httpResponse(status: status, body: body, contentType: contentType)
    }

    // MARK: - Routing

    @MainActor
    private func route(_ fullPath: String) -> (Int, String, String) {
        guard let comps = URLComponents(string: "http://localhost" + fullPath) else {
            return (400, #"{"error":"bad path"}"#, "application/json")
        }
        let path = comps.path
        let q = Dictionary(
            uniqueKeysWithValues: (comps.queryItems ?? []).compactMap { item -> (String, String)? in
                item.value.map { (item.name, $0) }
            }
        )

        switch path {
        case "/session":
            guard let data = try? WireTap.exportSessionData(),
                  let json = String(data: data, encoding: .utf8) else {
                return (500, #"{"error":"encode failed"}"#, "application/json")
            }
            return (200, json, "application/json")

        case "/overview":
            return (200, overviewJSON(), "application/json")

        case "/timeline":
            var opts = LLMExportOptions()
            if let kinds = q["kinds"] {
                let streams = kinds.split(separator: ",")
                    .compactMap { LLMExportOptions.Stream(rawString: String($0)) }
                if !streams.isEmpty { opts.include = Set(streams) }
            }
            if let limit = q["limit"].flatMap(Int.init) { opts.maxEntriesPerStream = limit }
            return (200, WireTap.exportForLLM(opts), "text/plain; charset=utf-8")

        case "/ble":
            return (200, bleJSON(q: q), "application/json")

        case "/network/failures":
            return (200, networkFailuresJSON(q: q), "application/json")

        case "/nfc":
            return (200, nfcJSON(), "application/json")

        default:
            return (404, #"{"error":"not found"}"#, "application/json")
        }
    }

    // MARK: - Route bodies

    @MainActor
    private func overviewJSON() -> String {
        let session = WireTap.makeSession()
        let netFails = session.network.filter { $0.error != nil || $0.statusCode.map { $0 < 200 || $0 >= 300 } == true }
        let bleErrors = session.ble.filter { $0.error != nil }
        let nfcErrors = session.nfc.filter { $0.error != nil }
        let obj: [String: Any] = [
            "network": session.network.count,
            "ble": session.ble.count,
            "nfc": session.nfc.count,
            "networkFailures": netFails.count,
            "bleErrors": bleErrors.count,
            "nfcErrors": nfcErrors.count,
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: obj, options: .prettyPrinted),
              let json = String(data: data, encoding: .utf8) else { return "{}" }
        return json
    }

    @MainActor
    private func bleJSON(q: [String: String]) -> String {
        var rows = WireTap.makeSession().ble
        if let type_ = q["type"] { rows = rows.filter { $0.type.caseInsensitiveCompare(type_) == .orderedSame } }
        if let uuid = q["uuid"] { rows = rows.filter { ($0.uuid ?? "").localizedCaseInsensitiveContains(uuid) } }
        if let device = q["device"] { rows = rows.filter { ($0.device ?? "").localizedCaseInsensitiveContains(device) } }
        let limit = q["limit"].flatMap(Int.init) ?? 100
        return encodeJSON(Array(rows.prefix(limit)))
    }

    @MainActor
    private func networkFailuresJSON(q: [String: String]) -> String {
        let limit = q["limit"].flatMap(Int.init) ?? 20
        let fails = WireTap.makeSession().network.filter {
            $0.error != nil || $0.statusCode.map { $0 < 200 || $0 >= 300 } == true
        }
        return encodeJSON(Array(fails.prefix(limit)))
    }

    @MainActor
    private func nfcJSON() -> String {
        encodeJSON(WireTap.makeSession().nfc)
    }

    private func encodeJSON<T: Encodable>(_ value: T) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(value),
              let json = String(data: data, encoding: .utf8) else { return "[]" }
        return json
    }

    // MARK: - HTTP formatting

    private func httpResponse(
        status: Int,
        body: String,
        contentType: String = "application/json; charset=utf-8",
        extra: String? = nil
    ) -> String {
        var lines = [
            "HTTP/1.1 \(status) \(statusPhrase(status))",
            "Content-Type: \(contentType)",
            "Content-Length: \(body.utf8.count)",
            "Connection: close",
            "X-WireTap-Bridge: 1",
        ]
        if let extra { lines.append(extra) }
        lines += ["", body]
        return lines.joined(separator: "\r\n")
    }

    private func statusPhrase(_ code: Int) -> String {
        switch code {
        case 200: return "OK"
        case 400: return "Bad Request"
        case 404: return "Not Found"
        case 405: return "Method Not Allowed"
        case 500: return "Internal Server Error"
        default:  return "Unknown"
        }
    }

    private func send(_ response: String, on conn: NWConnection) {
        conn.send(content: Data(response.utf8), completion: .contentProcessed { _ in conn.cancel() })
    }
}

// MARK: - LLMExportOptions.Stream helper (no RawRepresentable on the enum)

private extension LLMExportOptions.Stream {
    init?(rawString: String) {
        switch rawString.lowercased() {
        case "network": self = .network
        case "ble":     self = .ble
        case "nfc":     self = .nfc
        default:        return nil
        }
    }
}

// MARK: - WireTap public API

public extension WireTap {

    /// Start a read-only HTTP debug bridge on 127.0.0.1 for the `wiretap-mcp` live mode.
    ///
    /// The bridge is localhost-only and serves no write surface. Configure the MCP server
    /// with `WIRETAP_BRIDGE_URL=http://127.0.0.1:<port>` to enable live queries.
    ///
    /// ```swift
    /// #if DEBUG
    /// WireTap.startLocalBridge()          // default port 8787
    /// #endif
    /// ```
    static func startLocalBridge(port: UInt16 = 8787) {
        guard _localBridge == nil else { return }
        let bridge = LocalBridge(port: port)
        _localBridge = bridge
        Task {
            do { try await bridge.start() }
            catch { wiretapLog.error("WireTap.startLocalBridge failed: \(error)") }
        }
    }

    /// Stop the local bridge started by `startLocalBridge()`.
    static func stopLocalBridge() {
        _localBridge?.stop()
        _localBridge = nil
    }

    // Internal — for testing
    internal static var _localBridge: LocalBridge?
}
#endif
