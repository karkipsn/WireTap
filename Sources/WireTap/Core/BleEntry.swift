import Foundation

// MARK: - BleEventType

public enum BleEventType: String, CaseIterable, Sendable, Codable {
    case connected       = "Connected"
    case disconnected    = "Disconnected"
    case connecting      = "Connecting"
    case reconnecting    = "Reconnecting"
    case serviceDiscovered = "Services"
    case characteristicRead  = "Read"
    case characteristicWrite = "Write"
    case notification    = "Notify"
    case indication      = "Indicate"
    case pairingStarted  = "Pairing"
    case pairingSuccess  = "Paired"
    case pairingFailed   = "Pair Fail"
    case authStarted     = "Auth"
    case authSuccess     = "Auth OK"
    case authFailed      = "Auth Fail"
    case mtuNegotiated   = "MTU"
    case rssi            = "RSSI"
    case error           = "Error"
    case info            = "Info"

    public var isError: Bool {
        switch self {
        case .disconnected, .pairingFailed, .authFailed, .error: return true
        default: return false
        }
    }

    public var isSuccess: Bool {
        switch self {
        case .connected, .pairingSuccess, .authSuccess: return true
        default: return false
        }
    }

    public var symbol: String {
        switch self {
        case .connected:         return "checkmark.circle.fill"
        case .disconnected:      return "xmark.circle.fill"
        case .connecting,
             .reconnecting:      return "arrow.clockwise"
        case .serviceDiscovered: return "list.bullet"
        case .characteristicRead:  return "arrow.down.circle"
        case .characteristicWrite: return "arrow.up.circle"
        case .notification,
             .indication:        return "bell.circle"
        case .pairingStarted,
             .pairingSuccess,
             .pairingFailed:     return "lock.circle"
        case .authStarted,
             .authSuccess,
             .authFailed:        return "key.horizontal"
        case .mtuNegotiated:     return "ruler"
        case .rssi:              return "antenna.radiowaves.left.and.right"
        case .error:             return "exclamationmark.triangle.fill"
        case .info:              return "info.circle"
        }
    }
}

// MARK: - BleEntry

public struct BleEntry: Identifiable, Sendable, Codable {
    public let id: UUID
    public let date: Date
    public let type: BleEventType
    /// Service or characteristic UUID, if applicable.
    public let uuid: String?
    /// Device peripheral name / identifier.
    public let device: String?
    /// Raw bytes — shown as hex + ASCII.
    public let data: Data?
    /// Human-readable summary (e.g. "MTU=247", "RSSI=-62 dBm").
    public let detail: String?
    /// Error message, if this is an error event.
    public let error: String?
    /// Named fields produced by a registered decoder for this characteristic (TRACER-005), or nil.
    public let decoded: [String: String]?

    public init(
        id: UUID = UUID(),
        date: Date = Date(),
        type: BleEventType,
        uuid: String? = nil,
        device: String? = nil,
        data: Data? = nil,
        detail: String? = nil,
        error: String? = nil,
        decoded: [String: String]? = nil
    ) {
        self.id = id
        self.date = date
        self.type = type
        self.uuid = uuid
        self.device = device
        self.data = data
        self.detail = detail
        self.error = error
        self.decoded = decoded
    }

    /// A copy with decoded fields attached (used by `BleStore` at log time).
    func withDecoded(_ fields: [String: String]) -> BleEntry {
        BleEntry(id: id, date: date, type: type, uuid: uuid, device: device,
                 data: data, detail: detail, error: error, decoded: fields)
    }

    /// Hex representation of data bytes.
    public var hexString: String? {
        guard let data, !data.isEmpty else { return nil }
        return data.map { String(format: "%02X", $0) }.joined(separator: " ")
    }

    /// ASCII representation — non-printable bytes shown as ".".
    public var asciiString: String? {
        guard let data, !data.isEmpty else { return nil }
        return String(data.map { ($0 >= 32 && $0 < 127) ? Character(UnicodeScalar($0)) : "." })
    }
}
