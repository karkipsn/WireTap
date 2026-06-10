import Foundation

// MARK: - NfcEventType

public enum NfcEventType: String, CaseIterable, Sendable, Codable {
    case scanStarted     = "Scan Started"
    case tagDetected     = "Tag Detected"
    case ndefRead        = "NDEF Read"
    case recordParsed    = "Record Parsed"
    case iosTrustDecoded = "IosTrust"
    case apduSent        = "APDU →"
    case apduReceived    = "APDU ←"
    case scanCompleted   = "Completed"
    case scanFailed      = "Failed"
    case cancelled       = "Cancelled"

    public var isError: Bool {
        self == .scanFailed
    }

    public var isSuccess: Bool {
        self == .scanCompleted || self == .iosTrustDecoded
    }

    public var symbol: String {
        switch self {
        case .scanStarted:     return "sensor.tag.radiowaves.forward"
        case .tagDetected:     return "tag.fill"
        case .ndefRead:        return "doc.text.fill"
        case .recordParsed:    return "list.bullet.rectangle"
        case .iosTrustDecoded: return "checkmark.seal.fill"
        case .apduSent:        return "arrow.up.circle"
        case .apduReceived:    return "arrow.down.circle"
        case .scanCompleted:   return "checkmark.circle.fill"
        case .scanFailed:      return "xmark.circle.fill"
        case .cancelled:       return "slash.circle"
        }
    }
}

// MARK: - NfcEntry

public struct NfcEntry: Identifiable, Sendable, Codable {
    public let id: UUID
    public let date: Date
    public let type: NfcEventType
    /// Tag technology / NDEF MIME type / APDU class byte description.
    public let descriptor: String?
    /// Human-readable summary line.
    public let detail: String?
    /// Raw payload bytes (NDEF record payload, APDU data, etc.).
    public let data: Data?
    /// Error message when type is `.scanFailed`.
    public let error: String?

    public init(
        id: UUID = UUID(),
        date: Date = Date(),
        type: NfcEventType,
        descriptor: String? = nil,
        detail: String? = nil,
        data: Data? = nil,
        error: String? = nil
    ) {
        self.id = id
        self.date = date
        self.type = type
        self.descriptor = descriptor
        self.detail = detail
        self.data = data
        self.error = error
    }

    public var hexString: String? {
        guard let data, !data.isEmpty else { return nil }
        return data.map { String(format: "%02X", $0) }.joined(separator: " ")
    }

    public var asciiString: String? {
        guard let data, !data.isEmpty else { return nil }
        return String(data.map { ($0 >= 32 && $0 < 127) ? Character(UnicodeScalar($0)) : "." })
    }
}
