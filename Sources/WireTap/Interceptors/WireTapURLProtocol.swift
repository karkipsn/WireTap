import Foundation

/// URLProtocol interceptor that captures all HTTP traffic into WireTap.network.
///
/// Register by injecting it into your URLSessionConfiguration before building
/// the URLSession. The SDK layer (AppApiClient) stays unaware of WireTap —
/// the app layer injects the configured session at startup.
///
/// Usage (app layer, #if DEBUG):
/// ```swift
/// let config = WireTapURLProtocol.makeSessionConfiguration()
/// let client = AppApiClient(configuration: config)
/// ```
public final class WireTapURLProtocol: URLProtocol {

    // Marks requests already being handled to prevent infinite recursion.
    private static let handledKey = "WireTapURLProtocolHandled"

    /// One shared forwarding session reused for every intercepted request. Creating a
    /// `URLSession` per request (and never invalidating it) leaks a session each time.
    /// `.default` config has no WireTapURLProtocol registered, so forwarding can't recurse.
    private static let forwardingSession = URLSession(configuration: .default)

    private var dataTask: URLSessionDataTask?
    private var startDate = Date()
    private var collectedData = Data()

    // MARK: - URLProtocol overrides

    override public class func canInit(with request: URLRequest) -> Bool {
        URLProtocol.property(forKey: handledKey, in: request) == nil
    }

    override public class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override public func startLoading() {
        startDate = Date()
        collectedData = Data()

        // Tag the outgoing request so canInit returns false → no infinite recursion.
        let mutableRequest = (request as NSURLRequest).mutableCopy() as! NSMutableURLRequest
        URLProtocol.setProperty(true, forKey: Self.handledKey, in: mutableRequest)

        // Capture body before URLSession may replace it with a stream.
        let capturedBody = requestBody(from: request)

        dataTask = Self.forwardingSession.dataTask(with: mutableRequest as URLRequest) { [weak self] data, response, error in
            guard let self else { return }

            if let error {
                self.client?.urlProtocol(self, didFailWithError: error)
                self.recordFailure(body: capturedBody, error: error)
                return
            }

            if let response {
                self.client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            }
            if let data {
                self.collectedData.append(data)
                self.client?.urlProtocol(self, didLoad: data)
            }
            self.client?.urlProtocolDidFinishLoading(self)
            self.recordSuccess(body: capturedBody, response: response as? HTTPURLResponse, data: data)
        }
        dataTask?.resume()
    }

    override public func stopLoading() {
        dataTask?.cancel()
    }

    // MARK: - Private helpers

    /// Reads the request body from httpBody or httpBodyStream (URLSession may convert one to the other).
    private func requestBody(from request: URLRequest) -> Data? {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return nil }
        stream.open()
        defer { stream.close() }
        var buffer = [UInt8](repeating: 0, count: 4096)
        var data = Data()
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            guard count > 0 else { break }
            data.append(contentsOf: buffer[0..<count])
        }
        return data.isEmpty ? nil : data
    }

    private func recordSuccess(body: Data?, response: HTTPURLResponse?, data: Data?) {
        let durationMs = Int(Date().timeIntervalSince(startDate) * 1000)
        let entry = NetworkEntry(
            method: request.httpMethod ?? "?",
            url: request.url?.absoluteString ?? "?",
            requestHeaders: redactedHeaders(request.allHTTPHeaderFields),
            requestBody: body.flatMap { String(data: $0, encoding: .utf8) },
            statusCode: response?.statusCode,
            responseHeaders: (response?.allHeaderFields as? [String: String]) ?? [:],
            responseBody: data.flatMap { String(data: $0, encoding: .utf8) },
            durationMs: durationMs
        )
        Task { @MainActor in WireTap.network.record(entry) }
    }

    private func recordFailure(body: Data?, error: Error) {
        let durationMs = Int(Date().timeIntervalSince(startDate) * 1000)
        let entry = NetworkEntry(
            method: request.httpMethod ?? "?",
            url: request.url?.absoluteString ?? "?",
            requestHeaders: redactedHeaders(request.allHTTPHeaderFields),
            requestBody: body.flatMap { String(data: $0, encoding: .utf8) },
            durationMs: durationMs,
            error: error.localizedDescription
        )
        Task { @MainActor in WireTap.network.record(entry) }
    }

    private func redactedHeaders(_ headers: [String: String]?) -> [String: String] {
        (headers ?? [:]).reduce(into: [String: String]()) { result, pair in
            result[pair.key] = pair.key == "Authorization" ? "Bearer [redacted]" : pair.value
        }
    }
}

// MARK: - Factory

public extension WireTapURLProtocol {
    /// Returns a URLSessionConfiguration with WireTapURLProtocol pre-registered
    /// and the provided timeouts applied. Inject this into your HTTP client.
    static func makeSessionConfiguration(
        requestTimeout: TimeInterval = 15,
        resourceTimeout: TimeInterval = 30
    ) -> URLSessionConfiguration {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = requestTimeout
        config.timeoutIntervalForResource = resourceTimeout
        config.protocolClasses = [WireTapURLProtocol.self] + (config.protocolClasses ?? [])
        return config
    }
}
