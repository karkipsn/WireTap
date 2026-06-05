import SwiftUI

// MARK: - NetworkListView

public struct NetworkListView: View {
    @ObservedObject private var store = WireTap.network
    @State private var searchText = ""
    @State private var methodFilter: String? = nil

    private let methods = ["GET", "POST", "PATCH", "PUT", "DELETE"]

    private var filtered: [NetworkEntry] {
        store.entries.filter { entry in
            let matchesSearch = searchText.isEmpty
                || entry.url.localizedCaseInsensitiveContains(searchText)
                || entry.statusLabel.contains(searchText)
            let matchesMethod = methodFilter == nil || entry.method == methodFilter
            return matchesSearch && matchesMethod
        }
    }

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            // Method filter chips
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    WireTapFilterChip(label: "All", isSelected: methodFilter == nil) {
                        methodFilter = nil
                    }
                    ForEach(methods, id: \.self) { method in
                        WireTapFilterChip(label: method, isSelected: methodFilter == method) {
                            methodFilter = methodFilter == method ? nil : method
                        }
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
            }

            Divider()

            if filtered.isEmpty {
                PlaceholderView(
                    title: "No Requests",
                    systemImage: "network.slash",
                    description: store.entries.isEmpty
                        ? "Requests will appear here once captured."
                        : "No results for current filter."
                )
            } else {
                List(filtered) { entry in
                    NavigationLink(destination: NetworkDetailView(entry: entry)) {
                        NetworkRowView(entry: entry)
                    }
                    .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                }
                .listStyle(.plain)
            }
        }
        .searchable(text: $searchText, prompt: "Search URL or status")
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

struct NetworkRowView: View {
    let entry: NetworkEntry

    var body: some View {
        HStack(spacing: 10) {
            // Method badge
            Text(entry.method)
                .font(.caption2.monospaced().bold())
                .foregroundStyle(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(methodColor)
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .fixedSize()

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.url)
                    .font(.caption.monospaced())
                    .lineLimit(2)
                    .truncationMode(.middle)
                Text(entry.date.formatted(date: .omitted, time: .standard))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(entry.statusLabel)
                    .font(.caption.bold())
                    .foregroundStyle(statusColor)
                Text("\(entry.durationMs)ms")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var methodColor: Color {
        switch entry.method {
        case "GET":    return .blue
        case "POST":   return .indigo
        case "PATCH":  return .orange
        case "PUT":    return .purple
        case "DELETE": return .red
        default:       return .gray
        }
    }

    private var statusColor: Color {
        guard let code = entry.statusCode else { return .secondary }
        switch code {
        case 200...299: return .green
        case 300...399: return .orange
        case 400...499: return .red
        default:        return .red
        }
    }
}
