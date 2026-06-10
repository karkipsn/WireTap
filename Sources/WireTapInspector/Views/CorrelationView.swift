import SwiftUI

// MARK: - CorrelationView (TRACER-007)

/// Shows cross-radio "episodes" — an NFC tap, the BLE attempt it triggered, and the
/// network calls that followed, grouped by time proximity.
public struct CorrelationView: View {
    @ObservedObject private var network = WireTap.network
    @ObservedObject private var ble = WireTap.ble
    @ObservedObject private var nfc = WireTap.nfc

    public init() {}

    public var body: some View {
        let episodes = Array(WireTap.correlatedEpisodes().reversed()) // newest first

        Group {
            if episodes.isEmpty {
                PlaceholderView(
                    title: "No Episodes",
                    systemImage: "point.3.connected.trianglepath.dotted",
                    description: "Cross-radio episodes appear here once NFC / BLE / network activity is captured."
                )
            } else {
                List {
                    ForEach(episodes) { episode in
                        Section {
                            ForEach(episode.items, id: \.entryId) { item in
                                EpisodeRow(item: item)
                            }
                        } header: {
                            EpisodeHeader(episode: episode)
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle("Correlation")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}

private struct EpisodeHeader: View {
    let episode: CorrelatedEpisode

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: episode.trigger.symbol)
                .foregroundStyle(episode.trigger.color)
            VStack(alignment: .leading, spacing: 1) {
                Text(episode.trigger.label)
                    .font(.subheadline.weight(.semibold))
                Text("nfc \(episode.nfcCount) · ble \(episode.bleCount) · net \(episode.networkCount)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(String(format: "%.1fs", episode.duration))
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
        }
        .textCase(nil)
        .padding(.vertical, 4)
    }
}

private struct EpisodeRow: View {
    let item: TimelineItem

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(item.kind.label.uppercased())
                .font(.caption2.bold())
                .foregroundStyle(item.kind.color)
                .frame(width: 56, alignment: .leading)
            VStack(alignment: .leading, spacing: 1) {
                Text(timeOnly(item.timestamp))
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                Text(item.summary)
                    .font(.callout)
                    .lineLimit(2)
            }
        }
    }

    private func timeOnly(_ iso: String) -> String {
        guard let t = iso.split(separator: "T").last else { return iso }
        return String(t.replacingOccurrences(of: "Z", with: ""))
    }
}

private extension EpisodeTrigger {
    var label: String {
        switch self {
        case .nfcTap:     return "NFC tap"
        case .bleConnect: return "BLE connection"
        case .network:    return "Network activity"
        case .other:      return "Activity"
        }
    }
    var color: Color {
        switch self {
        case .nfcTap:     return .orange
        case .bleConnect: return .purple
        case .network:    return .blue
        case .other:      return .secondary
        }
    }
    var symbol: String {
        switch self {
        case .nfcTap:     return "sensor.tag.radiowaves.forward"
        case .bleConnect: return "dot.radiowaves.left.and.right"
        case .network:    return "network"
        case .other:      return "circle"
        }
    }
}
