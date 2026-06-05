import SwiftUI

// MARK: - BleDetailView

public struct BleDetailView: View {
    public let entry: BleEntry

    public init(entry: BleEntry) { self.entry = entry }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {

                // Header summary card
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

                // Fields
                if let device = entry.device {
                    InfoBlock(title: "Device", content: device)
                }
                if let uuid = entry.uuid {
                    InfoBlock(title: "UUID", content: uuid, mono: true)
                }
                if let detail = entry.detail {
                    InfoBlock(title: "Detail", content: detail)
                }
                if let error = entry.error {
                    InfoBlock(title: "Error", content: error, tint: .red)
                }

                // Decoded fields (TRACER-005) — shown above raw bytes when a decoder is registered.
                if let decoded = entry.decoded, !decoded.isEmpty {
                    InfoBlock(
                        title: "Decoded",
                        content: decoded.sorted { $0.key < $1.key }
                            .map { "\($0.key): \($0.value)" }
                            .joined(separator: "\n"),
                        mono: true,
                        tint: .green
                    )
                }

                // Data section
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
        case .characteristicRead:  return .blue
        case .characteristicWrite: return .orange
        case .notification, .indication: return .purple
        default: return .accentColor
        }
    }

    private var shareText: String {
        var lines: [String] = [
            "[\(entry.type.rawValue)] \(entry.date.formatted())"
        ]
        if let d  = entry.device { lines.append("Device: \(d)") }
        if let u  = entry.uuid   { lines.append("UUID: \(u)") }
        if let dt = entry.detail { lines.append("Detail: \(dt)") }
        if let e  = entry.error  { lines.append("Error: \(e)") }
        if let dec = entry.decoded, !dec.isEmpty {
            lines.append("Decoded: " + dec.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: ", "))
        }
        if let hex = entry.hexString { lines.append("Hex: \(hex)") }
        if let asc = entry.asciiString { lines.append("ASCII: \(asc)") }
        return lines.joined(separator: "\n")
    }
}
