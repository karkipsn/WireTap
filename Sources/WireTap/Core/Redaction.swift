import Foundation

// MARK: - TRACER-010 — Configurable Redaction Rules

/// Rules for masking secrets before any entry reaches a sink (disk, export, MCP).
public struct WireTapRedactionConfig: Sendable {
    /// Header names to redact (matched case-insensitively).
    public var redactedHeaders: Set<String>
    /// JSON body keys whose string value is masked (matched case-insensitively).
    public var redactedBodyKeys: [String]
    /// Replacement string.
    public var placeholder: String

    public init(redactedHeaders: Set<String>, redactedBodyKeys: [String], placeholder: String = "[redacted]") {
        self.redactedHeaders = Set(redactedHeaders.map { $0.lowercased() })
        self.redactedBodyKeys = redactedBodyKeys
        self.placeholder = placeholder
    }

    /// Sensible defaults covering the usual auth/secret carriers.
    public static let `default` = WireTapRedactionConfig(
        redactedHeaders: ["authorization", "cookie", "set-cookie", "x-api-key", "x-auth-token", "proxy-authorization"],
        redactedBodyKeys: ["password", "token", "access_token", "refresh_token", "secret", "api_key", "apikey", "authorization"]
    )

    /// Allow `WireTap.redaction.redactedHeaders.insert("x")` to keep the lowercased invariant.
    public mutating func addHeader(_ name: String) { redactedHeaders.insert(name.lowercased()) }
}

enum WireTapRedaction {
    /// Return a copy of the entry with sensitive headers and JSON body fields masked.
    /// Pure string work (no JSON re-serialization) → deterministic.
    static func redacted(_ entry: NetworkEntry, config: WireTapRedactionConfig) -> NetworkEntry {
        NetworkEntry(
            id: entry.id,
            date: entry.date,
            method: entry.method,
            url: entry.url,
            requestHeaders: redactHeaders(entry.requestHeaders, config),
            requestBody: redactBody(entry.requestBody, config),
            statusCode: entry.statusCode,
            responseHeaders: redactHeaders(entry.responseHeaders, config),
            responseBody: redactBody(entry.responseBody, config),
            durationMs: entry.durationMs,
            error: entry.error
        )
    }

    private static func redactHeaders(_ headers: [String: String], _ config: WireTapRedactionConfig) -> [String: String] {
        guard !config.redactedHeaders.isEmpty else { return headers }
        var result = headers
        for key in headers.keys where config.redactedHeaders.contains(key.lowercased()) {
            result[key] = config.placeholder
        }
        return result
    }

    /// Mask `"key":"value"` for each configured key. Note: matches simple JSON string
    /// values (no embedded escaped quotes) — sufficient for typical tokens; documented limit.
    private static func redactBody(_ body: String?, _ config: WireTapRedactionConfig) -> String? {
        guard let body, !body.isEmpty, !config.redactedBodyKeys.isEmpty else { return body }
        var result = body
        for key in config.redactedBodyKeys {
            let escaped = NSRegularExpression.escapedPattern(for: key)
            let pattern = "(\"\(escaped)\"\\s*:\\s*)\"[^\"]*\""
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { continue }
            let range = NSRange(result.startIndex..., in: result)
            let template = "$1\"\(config.placeholder)\""
            result = regex.stringByReplacingMatches(in: result, options: [], range: range, withTemplate: template)
        }
        return result
    }
}
