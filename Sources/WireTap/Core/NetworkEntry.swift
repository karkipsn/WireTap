import Foundation

// MARK: - NetworkEntry

public struct NetworkEntry: Identifiable, Sendable, Codable {
    public let id: UUID
    public let date: Date
    public let method: String
    public let url: String
    public let requestHeaders: [String: String]
    public let requestBody: String?
    public let statusCode: Int?
    public let responseHeaders: [String: String]
    public let responseBody: String?
    public let durationMs: Int
    public let error: String?

    public init(
        id: UUID = UUID(),
        date: Date = Date(),
        method: String,
        url: String,
        requestHeaders: [String: String] = [:],
        requestBody: String? = nil,
        statusCode: Int? = nil,
        responseHeaders: [String: String] = [:],
        responseBody: String? = nil,
        durationMs: Int,
        error: String? = nil
    ) {
        self.id = id
        self.date = date
        self.method = method
        self.url = url
        self.requestHeaders = requestHeaders
        self.requestBody = requestBody
        self.statusCode = statusCode
        self.responseHeaders = responseHeaders
        self.responseBody = responseBody
        self.durationMs = durationMs
        self.error = error
    }

    public var isSuccess: Bool {
        guard let code = statusCode else { return false }
        return (200...299).contains(code)
    }

    public var statusLabel: String {
        if let code = statusCode { return "\(code)" }
        return error != nil ? "ERR" : "…"
    }

    /// cURL command reconstructed from the captured request.
    public var curlCommand: String {
        var parts = ["curl -X \(method)"]
        for (key, val) in requestHeaders.sorted(by: { $0.key < $1.key }) {
            let escaped = val.replacingOccurrences(of: "'", with: "'\\''")
            parts.append("-H '\(key): \(escaped)'")
        }
        if let body = requestBody {
            let escaped = body.replacingOccurrences(of: "'", with: "'\\''")
            parts.append("-d '\(escaped)'")
        }
        parts.append("'\(url)'")
        return parts.joined(separator: " \\\n  ")
    }
}
