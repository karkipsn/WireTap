import Foundation

// MARK: - TRACER-006 — Connection Lifecycle

public enum LifecyclePhase: String, Sendable {
    case connecting, connected, services, mtu, pairing, paired, pairFailed
    case authStarted, authed, authFailed, streaming, error, disconnected
}

public struct LifecycleStep: Sendable, Equatable {
    public let phase: LifecyclePhase
    public let date: Date
    public let detail: String?
}

public enum ConnectionOutcome: Sendable, Equatable {
    case inProgress
    case streaming
    case disconnected(reason: String?)
    case failed(phase: LifecyclePhase, reason: String?)
}

public struct ConnectionAttempt: Identifiable, Sendable {
    public let id: UUID
    public let device: String?
    public let start: Date
    public let end: Date?
    public let steps: [LifecycleStep]
    public let outcome: ConnectionOutcome
    public var duration: TimeInterval? { end.map { $0.timeIntervalSince(start) } }
}

public extension BleStore {
    /// Group captured BLE events into per-connection attempts with an outcome.
    /// Pure derivation over `entries` (no new capture).
    func connectionAttempts() -> [ConnectionAttempt] {
        let chrono = entries.sorted { $0.date < $1.date }
        var attempts: [ConnectionAttempt] = []
        var builder: AttemptBuilder?

        func close() {
            if let b = builder { attempts.append(b.build()); builder = nil }
        }

        for e in chrono {
            guard let phase = Self.phase(for: e.type) else { continue } // ignore read/write/rssi/info
            if builder == nil { builder = AttemptBuilder(device: e.device, start: e.date) }
            builder?.add(phase: phase, date: e.date, detail: e.error ?? e.detail)
            if phase == .disconnected {
                builder?.end = e.date
                close()
            }
        }
        close()
        return attempts
    }

    /// Map a BLE event type to a lifecycle phase, or nil if it's not part of the lifecycle.
    private static func phase(for type: BleEventType) -> LifecyclePhase? {
        switch type {
        case .connecting, .reconnecting: return .connecting
        case .connected:                 return .connected
        case .serviceDiscovered:         return .services
        case .mtuNegotiated:             return .mtu
        case .pairingStarted:            return .pairing
        case .pairingSuccess:            return .paired
        case .pairingFailed:             return .pairFailed
        case .authStarted:               return .authStarted
        case .authSuccess:               return .authed
        case .authFailed:                return .authFailed
        case .notification, .indication: return .streaming
        case .error:                     return .error
        case .disconnected:              return .disconnected
        case .characteristicRead, .characteristicWrite, .rssi, .info:
            return nil
        }
    }
}

// MARK: - Builder

private struct AttemptBuilder {
    let device: String?
    let start: Date
    var end: Date?
    private(set) var steps: [LifecycleStep] = []
    private var sawStreaming = false

    init(device: String?, start: Date) {
        self.device = device
        self.start = start
    }

    mutating func add(phase: LifecyclePhase, date: Date, detail: String?) {
        // Record streaming only once to avoid one row per notification.
        if phase == .streaming {
            guard !sawStreaming else { return }
            sawStreaming = true
        }
        steps.append(LifecycleStep(phase: phase, date: date, detail: detail))
    }

    func build() -> ConnectionAttempt {
        ConnectionAttempt(
            id: UUID(),
            device: device,
            start: start,
            end: end,
            steps: steps,
            outcome: outcome()
        )
    }

    private func outcome() -> ConnectionOutcome {
        if let s = steps.last(where: { $0.phase == .authFailed }) {
            return .failed(phase: .authFailed, reason: s.detail)
        }
        if let s = steps.last(where: { $0.phase == .pairFailed }) {
            return .failed(phase: .pairFailed, reason: s.detail)
        }
        if let s = steps.last(where: { $0.phase == .disconnected }) {
            return .disconnected(reason: s.detail)
        }
        if steps.contains(where: { $0.phase == .streaming }) {
            return .streaming
        }
        return .inProgress
    }
}
