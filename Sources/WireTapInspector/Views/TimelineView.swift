import SwiftUI

// MARK: - TimelineView (TRACER-002)

/// The unified, cross-stream timeline: BLE, NFC and network events merged in
/// ascending time order. This is the view no network-only inspector can show.
public struct TimelineView: View {
    @ObservedObject private var network = WireTap.network
    @ObservedObject private var ble = WireTap.ble
    @ObservedObject private var nfc = WireTap.nfc

    @State private var kindFilter: TimelineItem.Kind? = nil

    public init() {}

    private var items: [TimelineItem] {
        let all = WireTap.timeline()
        guard let kind = kindFilter else { return all }
        return all.filter { $0.kind == kind }
    }

    public var body: some View {
        VStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    WireTapFilterChip(label: "All", isSelected: kindFilter == nil) { kindFilter = nil }
                    ForEach(TimelineItem.Kind.allCases, id: \.self) { kind in
                        WireTapFilterChip(label: kind.label, isSelected: kindFilter == kind) {
                            kindFilter = kindFilter == kind ? nil : kind
                        }
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
            }

            Divider()

            // Cross-radio correlation (TRACER-007).
            if !items.isEmpty {
                NavigationLink {
                    CorrelationView()
                } label: {
                    Label("Correlated episodes", systemImage: "point.3.connected.trianglepath.dotted")
                        .font(.subheadline)
                        .padding(.horizontal)
                        .padding(.vertical, 10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                Divider()
                NavigationLink {
                    SessionDiffView()
                } label: {
                    Label("Compare with baseline", systemImage: "arrow.left.arrow.right")
                        .font(.subheadline)
                        .padding(.horizontal)
                        .padding(.vertical, 10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                Divider()
            }

            if items.isEmpty {
                PlaceholderView(
                    title: "No Events",
                    systemImage: "list.bullet.rectangle",
                    description: "Captured BLE, NFC and network events appear here in time order."
                )
            } else {
                List(items, id: \.entryId) { item in
                    TimelineRow(item: item)
                        .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                }
                .listStyle(.plain)
            }
        }
    }
}

// MARK: - Row

private struct TimelineRow: View {
    let item: TimelineItem

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            RoundedRectangle(cornerRadius: 2)
                .fill(item.kind.color)
                .frame(width: 3)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(item.kind.label.uppercased())
                        .font(.caption2.bold())
                        .foregroundStyle(item.kind.color)
                    Text(timeOnly(item.timestamp))
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                }
                Text(item.summary)
                    .font(.callout)
                    .foregroundStyle(.primary)
                    .lineLimit(3)
            }
        }
    }

    /// "2026-06-04T10:00:01.020Z" → "10:00:01.020"
    private func timeOnly(_ iso: String) -> String {
        guard let t = iso.split(separator: "T").last else { return iso }
        return String(t.replacingOccurrences(of: "Z", with: ""))
    }
}

// MARK: - Kind styling

extension TimelineItem.Kind: CaseIterable {
    public static var allCases: [TimelineItem.Kind] { [.network, .ble, .nfc] }

    var label: String {
        switch self {
        case .network: return "Network"
        case .ble:     return "BLE"
        case .nfc:     return "NFC"
        }
    }

    var color: Color {
        switch self {
        case .network: return .blue
        case .ble:     return .purple
        case .nfc:     return .orange
        }
    }
}
