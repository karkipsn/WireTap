import Foundation

// MARK: - TRACER-007 — Cross-Radio Correlation

public enum EpisodeTrigger: String, Sendable {
    case nfcTap, bleConnect, network, other
}

/// A time-clustered run of cross-stream events — e.g. an NFC tap, the BLE connection it
/// triggered, and the network calls that followed.
public struct CorrelatedEpisode: Identifiable, Sendable {
    public let id: UUID
    public let start: Date
    public let end: Date
    public let trigger: EpisodeTrigger
    public let nfcCount: Int
    public let bleCount: Int
    public let networkCount: Int
    public let items: [TimelineItem]
    public var duration: TimeInterval { end.timeIntervalSince(start) }
}

public extension WireTap {
    /// Cluster the unified timeline into episodes separated by quiet gaps > `maxGap` seconds.
    static func correlatedEpisodes(maxGap: TimeInterval = 60) -> [CorrelatedEpisode] {
        let rows = timelineEntries() // ascending (date, item)
        guard !rows.isEmpty else { return [] }

        var episodes: [CorrelatedEpisode] = []
        var bucket: [(date: Date, item: TimelineItem)] = [rows[0]]

        func flush() {
            guard let first = bucket.first, let last = bucket.last else { return }
            let items = bucket.map(\.item)
            episodes.append(CorrelatedEpisode(
                id: UUID(),
                start: first.date,
                end: last.date,
                trigger: trigger(for: first.item.kind),
                nfcCount: items.filter { $0.kind == .nfc }.count,
                bleCount: items.filter { $0.kind == .ble }.count,
                networkCount: items.filter { $0.kind == .network }.count,
                items: items
            ))
        }

        for row in rows.dropFirst() {
            if row.date.timeIntervalSince(bucket.last!.date) > maxGap {
                flush()
                bucket = [row]
            } else {
                bucket.append(row)
            }
        }
        flush()
        return episodes
    }

    private static func trigger(for kind: TimelineItem.Kind) -> EpisodeTrigger {
        switch kind {
        case .nfc:     return .nfcTap
        case .ble:     return .bleConnect
        case .network: return .network
        }
    }
}
