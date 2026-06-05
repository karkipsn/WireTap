import SwiftUI

// MARK: - NfcLogView

public struct NfcLogView: View {
    @ObservedObject private var store = WireTap.nfc
    @State private var searchText = ""
    @State private var typeFilter: NfcEventType? = nil

    private var filtered: [NfcEntry] {
        store.entries.filter { entry in
            let matchesType = typeFilter == nil || entry.type == typeFilter
            let matchesSearch = searchText.isEmpty
                || (entry.descriptor?.localizedCaseInsensitiveContains(searchText) ?? false)
                || (entry.detail?.localizedCaseInsensitiveContains(searchText) ?? false)
                || entry.type.rawValue.localizedCaseInsensitiveContains(searchText)
            return matchesType && matchesSearch
        }
    }

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    WireTapFilterChip(label: "All", isSelected: typeFilter == nil) {
                        typeFilter = nil
                    }
                    ForEach(NfcEventType.allCases, id: \.self) { type in
                        WireTapFilterChip(label: type.rawValue, isSelected: typeFilter == type) {
                            typeFilter = typeFilter == type ? nil : type
                        }
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
            }

            Divider()

            if filtered.isEmpty {
                PlaceholderView(
                    title: "No NFC Events",
                    systemImage: "sensor.tag.radiowaves.forward",
                    description: store.entries.isEmpty
                        ? "Tap an NFC tag to capture events."
                        : "No events match the current filter."
                )
            } else {
                List(filtered) { entry in
                    NavigationLink(destination: NfcDetailView(entry: entry)) {
                        NfcRowView(entry: entry)
                    }
                    .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                }
                .listStyle(.plain)
            }
        }
        .searchable(text: $searchText, prompt: "Search MIME type, detail")
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

struct NfcRowView: View {
    let entry: NfcEntry

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
                    if let descriptor = entry.descriptor {
                        Text(descriptor)
                            .font(.caption2.monospaced())
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
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
        case .apduSent:     return .orange
        case .apduReceived: return .blue
        case .ndefRead, .recordParsed: return .purple
        default:            return .secondary
        }
    }
}

// MARK: - Detail

public struct NfcDetailView: View {
    public let entry: NfcEntry

    public init(entry: NfcEntry) { self.entry = entry }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {

                // Header card
                HStack(spacing: 12) {
                    Image(systemName: entry.type.symbol)
                        .font(.system(size: 28))
                        .foregroundStyle(headerColor)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(entry.type.rawValue)
                            .font(.headline)
                            .foregroundStyle(headerColor)
                        Text(entry.date.formatted(date: .abbreviated, time: .standard))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding()
                .background(headerColor.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 12))

                if let descriptor = entry.descriptor {
                    InfoBlock(title: "Type / MIME", content: descriptor, mono: true)
                }
                if let detail = entry.detail {
                    InfoBlock(title: "Detail", content: detail)
                }
                if let error = entry.error {
                    InfoBlock(title: "Error", content: error, tint: .red)
                }
                if let hex = entry.hexString {
                    InfoBlock(title: "Hex (\(entry.data!.count) bytes)", content: hex, mono: true)
                }
                if let ascii = entry.asciiString {
                    InfoBlock(title: "ASCII", content: ascii, mono: true)
                }
            }
            .padding()
        }
        .navigationTitle(entry.type.rawValue)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                ShareLink(item: shareText,
                          preview: SharePreview(entry.type.rawValue,
                                                image: Image(systemName: entry.type.symbol))) {
                    Image(systemName: "square.and.arrow.up")
                }
            }
        }
    }

    private var headerColor: Color {
        if entry.type.isError   { return .red }
        if entry.type.isSuccess { return .green }
        switch entry.type {
        case .apduSent:     return .orange
        case .apduReceived: return .blue
        case .ndefRead, .recordParsed: return .purple
        default:            return .accentColor
        }
    }

    private var shareText: String {
        var lines = ["[\(entry.type.rawValue)] \(entry.date.formatted())"]
        if let d = entry.descriptor { lines.append("Type: \(d)") }
        if let d = entry.detail     { lines.append("Detail: \(d)") }
        if let e = entry.error      { lines.append("Error: \(e)") }
        if let h = entry.hexString  { lines.append("Hex: \(h)") }
        if let a = entry.asciiString { lines.append("ASCII: \(a)") }
        return lines.joined(separator: "\n")
    }
}
