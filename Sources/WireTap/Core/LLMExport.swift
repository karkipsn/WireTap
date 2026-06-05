import Foundation

// MARK: - TRACER-003 — LLM-Optimized Export

/// Controls for rendering a session as LLM-ingestible text.
public struct LLMExportOptions: Sendable {

    public enum Format: Sendable { case markdown, jsonl }
    public enum Stream: CaseIterable, Sendable { case network, ble, nfc }

    /// Output shape. `.markdown` is best for pasting into a chat; `.jsonl` for tools.
    public var format: Format = .markdown
    /// Which streams to include.
    public var include: Set<Stream> = Set(Stream.allCases)
    /// Max payload bytes shown per entry before truncation (`…+N more bytes`).
    public var maxPayloadBytes: Int = 256
    /// Max characters of a request/response body (shown on failed network calls).
    public var maxBodyChars: Int = 256
    /// Max entries kept per stream (newest), to bound token count.
    public var maxEntriesPerStream: Int = 200
    /// Prepend a self-describing schema legend so a model needs no prior knowledge.
    public var includeSchemaPreamble: Bool = true

    /// If set, only these BLE event types are exported (nil = all).
    public var bleTypes: Set<BleEventType>? = nil
    /// If set, only these NFC event types are exported (nil = all).
    public var nfcTypes: Set<NfcEventType>? = nil
    /// If set, only events whose rendered summary contains this text (case-insensitive).
    public var searchText: String? = nil

    public init() {}
}

public extension Set where Element == LLMExportOptions.Stream {
    /// All three streams.
    static var all: Set<LLMExportOptions.Stream> { Set(LLMExportOptions.Stream.allCases) }
}

// MARK: - Rendering

private struct RenderedEvent {
    let timestamp: String
    let kind: String // "net" | "ble" | "nfc"
    let summary: String
}

private enum LLMRenderer {

    static func truncatedHex(_ hex: String?, maxBytes: Int) -> String? {
        guard let hex, !hex.isEmpty else { return nil }
        let totalBytes = hex.count / 2
        guard totalBytes > maxBytes else { return hex }
        let shown = String(hex.prefix(maxBytes * 2))
        return "\(shown) …+\(totalBytes - maxBytes) more bytes"
    }

    static func truncatedText(_ text: String, maxChars: Int) -> String {
        guard text.count > maxChars else { return text }
        return String(text.prefix(maxChars)) + " …+\(text.count - maxChars) more chars"
    }

    /// A network entry is a "failure" if it errored or returned a non-2xx status.
    static func isFailure(_ e: NetworkRecord) -> Bool {
        if e.error != nil { return true }
        if let code = e.statusCode { return !(200...299).contains(code) }
        return false
    }

    /// Cap each stream to the newest N, collect cap-notes, and flatten to a sorted
    /// ascending event list.
    static func events(_ s: WireTapSession, _ o: LLMExportOptions) -> (events: [RenderedEvent], notes: [String]) {
        var out: [RenderedEvent] = []
        var notes: [String] = []

        let query = o.searchText?.lowercased()
        let bleAllowed = o.bleTypes.map { Set($0.map { String(describing: $0) }) }
        let nfcAllowed = o.nfcTypes.map { Set($0.map { String(describing: $0) }) }

        func matchesSearch(_ summary: String) -> Bool {
            guard let query, !query.isEmpty else { return true }
            return summary.lowercased().contains(query)
        }

        // Filter first, then cap — so the cap-note reflects the filtered count.
        func collect(_ name: String, _ all: [RenderedEvent]) {
            if all.count > o.maxEntriesPerStream {
                notes.append("\(name): showing newest \(o.maxEntriesPerStream) of \(all.count)")
            }
            out.append(contentsOf: all.suffix(o.maxEntriesPerStream))
        }

        if o.include.contains(.network) {
            let evs = s.network.compactMap { e -> RenderedEvent? in
                let status = e.error.map { "ERR(\($0))" } ?? (e.statusCode.map(String.init) ?? "?")
                var summary = "\(e.method) \(e.url) \(status) \(e.durationMs)ms"
                // Show request/response bodies only for failures (the usual clue), truncated.
                if isFailure(e) {
                    if let body = e.requestBody, !body.isEmpty { summary += " req=\(truncatedText(body, maxChars: o.maxBodyChars))" }
                    if let body = e.responseBody, !body.isEmpty { summary += " resp=\(truncatedText(body, maxChars: o.maxBodyChars))" }
                }
                guard matchesSearch(summary) else { return nil }
                return RenderedEvent(timestamp: e.timestamp, kind: "net", summary: summary)
            }
            collect("network", evs)
        }
        if o.include.contains(.ble) {
            let evs = s.ble.compactMap { e -> RenderedEvent? in
                if let bleAllowed, !bleAllowed.contains(e.type) { return nil }
                var parts = [e.type]
                if let v = e.uuid { parts.append("uuid=\(v)") }
                if let v = e.device { parts.append("device=\(v)") }
                if let v = truncatedHex(e.hex, maxBytes: o.maxPayloadBytes) { parts.append("hex=\(v)") }
                if let d = e.decoded, !d.isEmpty {
                    parts.append("{" + d.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: " ") + "}")
                }
                if let v = e.detail { parts.append("\"\(v)\"") }
                if let v = e.error { parts.append("ERR=\(v)") }
                let summary = parts.joined(separator: " ")
                guard matchesSearch(summary) else { return nil }
                return RenderedEvent(timestamp: e.timestamp, kind: "ble", summary: summary)
            }
            collect("ble", evs)
        }
        if o.include.contains(.nfc) {
            let evs = s.nfc.compactMap { e -> RenderedEvent? in
                if let nfcAllowed, !nfcAllowed.contains(e.type) { return nil }
                var parts = [e.type]
                if let v = e.descriptor { parts.append("desc=\(v)") }
                if let v = truncatedHex(e.hex, maxBytes: o.maxPayloadBytes) { parts.append("hex=\(v)") }
                if let v = e.detail { parts.append("\"\(v)\"") }
                if let v = e.error { parts.append("ERR=\(v)") }
                let summary = parts.joined(separator: " ")
                guard matchesSearch(summary) else { return nil }
                return RenderedEvent(timestamp: e.timestamp, kind: "nfc", summary: summary)
            }
            collect("nfc", evs)
        }

        out.sort { a, b in
            if a.timestamp != b.timestamp { return a.timestamp < b.timestamp }
            return a.kind < b.kind
        }
        return (out, notes)
    }

    static func markdown(_ s: WireTapSession, _ o: LLMExportOptions) -> String {
        var lines: [String] = ["# WireTap session — connected-device runtime trace"]

        if o.includeSchemaPreamble {
            lines.append("""
            Schema: each timeline line is one event — `- <ts> <stream> <fields>`.
              net: method url status durMs (req/resp bodies shown on failures)
              ble: type uuid device hex(<=\(o.maxPayloadBytes)B) detail err
              nfc: type descriptor hex(<=\(o.maxPayloadBytes)B) detail err
            Times ISO-8601 UTC. "…+N more bytes" / "…+N more chars" mark truncation. Secrets redacted.
            """)
        }

        let total = s.network.count + s.ble.count + s.nfc.count
        let range = s.range.map { "\($0.start) → \($0.end)" } ?? "no events"
        lines.append("App: \(s.app.bundleId) \(s.app.version) | OS: \(s.environment.os) \(s.environment.osVersion) | Events: \(total) over \(range)")

        let (evs, notes) = events(s, o)
        lines.append("")
        lines.append("## timeline (ascending)")
        for n in notes { lines.append("(\(n))") }
        if evs.isEmpty {
            lines.append("(no events captured)")
        } else {
            for e in evs { lines.append("- \(e.timestamp) \(e.kind) \(e.summary)") }
        }
        return lines.joined(separator: "\n")
    }

    static func jsonl(_ s: WireTapSession, _ o: LLMExportOptions) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]

        let total = s.network.count + s.ble.count + s.nfc.count
        let header = LLMHeader(
            schemaDoc: o.includeSchemaPreamble
                ? "wiretap-llm-1; events: {t,k,...}; k in net|ble|nfc; hex truncated; secrets redacted"
                : nil,
            app: "\(s.app.bundleId) \(s.app.version)",
            os: "\(s.environment.os) \(s.environment.osVersion)",
            events: total,
            range: s.range
        )

        var out: [String] = []
        if let line = try? encoder.encode(header), let str = String(data: line, encoding: .utf8) {
            out.append(str)
        }

        let (evs, _) = events(s, o)
        for e in evs {
            let obj = LLMLine(t: e.timestamp, k: e.kind, summary: e.summary)
            if let line = try? encoder.encode(obj), let str = String(data: line, encoding: .utf8) {
                out.append(str)
            }
        }
        if evs.isEmpty {
            // Keep the "no events" signal present in JSONL too.
            out.append("{\"note\":\"no events captured\"}")
        }
        return out.joined(separator: "\n")
    }
}

private struct LLMHeader: Encodable {
    let schemaDoc: String?
    let app: String
    let os: String
    let events: Int
    let range: WireTapDateRange?
    enum CodingKeys: String, CodingKey {
        case schemaDoc = "_schema", app, os, events, range
    }
}

private struct LLMLine: Encodable {
    let t: String
    let k: String
    let summary: String
}

// MARK: - WireTap entry points

public extension WireTap {
    /// Render the current capture as LLM-ingestible text.
    static func exportForLLM(_ options: LLMExportOptions = .init()) -> String {
        exportForLLM(makeSession(), options: options)
    }

    /// Render an already-captured session (e.g. imported) for an agent.
    static func exportForLLM(_ session: WireTapSession, options: LLMExportOptions = .init()) -> String {
        switch options.format {
        case .markdown: return LLMRenderer.markdown(session, options)
        case .jsonl:    return LLMRenderer.jsonl(session, options)
        }
    }
}
