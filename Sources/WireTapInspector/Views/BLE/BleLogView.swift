import SwiftUI

// MARK: - BleLogView

public struct BleLogView: View {
    @ObservedObject private var store = WireTap.ble
    @State private var searchText = ""
    @State private var typeFilter: BleEventType? = nil

    private var filtered: [BleEntry] {
        store.entries.filter { entry in
            let matchesType = typeFilter == nil || entry.type == typeFilter
            let matchesSearch = searchText.isEmpty
                || (entry.uuid?.localizedCaseInsensitiveContains(searchText) ?? false)
                || (entry.device?.localizedCaseInsensitiveContains(searchText) ?? false)
                || (entry.detail?.localizedCaseInsensitiveContains(searchText) ?? false)
                || entry.type.rawValue.localizedCaseInsensitiveContains(searchText)
            return matchesType && matchesSearch
        }
    }

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            // Event type filter chips
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    WireTapFilterChip(label: "All", isSelected: typeFilter == nil) {
                        typeFilter = nil
                    }
                    ForEach(BleEventType.allCases, id: \.self) { type in
                        WireTapFilterChip(label: type.rawValue, isSelected: typeFilter == type) {
                            typeFilter = typeFilter == type ? nil : type
                        }
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
            }

            Divider()

            // Derived connection-lifecycle view (TRACER-006).
            if !store.entries.isEmpty {
                NavigationLink {
                    ConnectionLifecycleView()
                } label: {
                    Label("Connection lifecycle", systemImage: "point.3.connected.trianglepath.dotted")
                        .font(.subheadline)
                        .padding(.horizontal)
                        .padding(.vertical, 10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                Divider()
            }

            if filtered.isEmpty {
                PlaceholderView(
                    title: "No BLE Events",
                    systemImage: "dot.radiowaves.left.and.right",
                    description: store.entries.isEmpty
                        ? "BLE events will appear here once captured."
                        : "No events match the current filter."
                )
            } else {
                List(filtered) { entry in
                    NavigationLink(destination: BleDetailView(entry: entry)) {
                        BleRowView(entry: entry)
                    }
                    .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                }
                .listStyle(.plain)
            }
        }
        .searchable(text: $searchText, prompt: "Search UUID, device, detail")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Clear") { store.clear() }
                    .foregroundStyle(.red)
                    .disabled(store.entries.isEmpty)
            }
        }
    }
}

// MARK: - Row

struct BleRowView: View {
    let entry: BleEntry

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: entry.type.symbol)
                .font(.system(size: 18))
                .foregroundStyle(iconColor)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(entry.type.rawValue)
                        .font(.caption.bold())
                        .foregroundStyle(iconColor)
                    if let device = entry.device {
                        Text(device)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                if let uuid = entry.uuid {
                    Text(uuid)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                if let detail = entry.detail {
                    Text(detail)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                if let data = entry.data {
                    Text("\(data.count)B")
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                }
                Text(entry.date.formatted(date: .omitted, time: .standard))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 2)
    }

    private var iconColor: Color {
        if entry.type.isError   { return .red }
        if entry.type.isSuccess { return .green }
        switch entry.type {
        case .characteristicRead:  return .blue
        case .characteristicWrite: return .orange
        case .notification, .indication: return .purple
        default: return .secondary
        }
    }
}
