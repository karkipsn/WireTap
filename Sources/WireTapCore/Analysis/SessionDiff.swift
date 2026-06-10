import Foundation

// MARK: - TRACER-008 — Session Diff

/// A normalized event identity used to match events across two runs (ids/timestamps differ).
public struct EventSignature: Sendable, Hashable {
    public let kind: TimelineItem.Kind
    public let key: String
}

public struct SessionDiff: Sendable {
    public let onlyInA: [EventSignature]
    public let onlyInB: [EventSignature]
    public let common: [EventSignature]
}

public extension WireTap {
    /// In-memory baseline for the "good run vs current" workflow.
    static var baselineSession: WireTapSession?

    /// Count-aware multiset diff of two sessions by normalized event signature.
    static func diff(_ a: WireTapSession, _ b: WireTapSession) -> SessionDiff {
        let countA = counted(signatures(of: a))
        let countB = counted(signatures(of: b))

        var onlyA: [EventSignature] = []
        var onlyB: [EventSignature] = []
        var common: [EventSignature] = []

        for sig in Set(countA.keys).union(countB.keys) {
            let ca = countA[sig] ?? 0
            let cb = countB[sig] ?? 0
            if min(ca, cb) > 0 { common += Array(repeating: sig, count: min(ca, cb)) }
            if ca > cb { onlyA += Array(repeating: sig, count: ca - cb) }
            if cb > ca { onlyB += Array(repeating: sig, count: cb - ca) }
        }

        let byKey: (EventSignature, EventSignature) -> Bool = { $0.key < $1.key }
        return SessionDiff(
            onlyInA: onlyA.sorted(by: byKey),
            onlyInB: onlyB.sorted(by: byKey),
            common: common.sorted(by: byKey)
        )
    }

    private static func signatures(of session: WireTapSession) -> [EventSignature] {
        var sigs: [EventSignature] = []
        sigs += session.ble.map { EventSignature(kind: .ble, key: "ble:\($0.type)") }
        sigs += session.nfc.map { EventSignature(kind: .nfc, key: "nfc:\($0.type)") }
        sigs += session.network.map {
            EventSignature(kind: .network, key: "net:\($0.method) \($0.url) \(statusClass($0))")
        }
        return sigs
    }

    private static func counted(_ sigs: [EventSignature]) -> [EventSignature: Int] {
        sigs.reduce(into: [:]) { $0[$1, default: 0] += 1 }
    }

    private static func statusClass(_ e: NetworkRecord) -> String {
        if e.error != nil { return "err" }
        guard let code = e.statusCode else { return "?" }
        return "\(code / 100)xx"
    }
}
