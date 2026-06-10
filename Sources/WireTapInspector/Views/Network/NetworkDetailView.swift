import SwiftUI

// MARK: - NetworkDetailView

public struct NetworkDetailView: View {
    public let entry: NetworkEntry
    @State private var section = 0

    public init(entry: NetworkEntry) { self.entry = entry }

    public var body: some View {
        VStack(spacing: 0) {
            // Summary strip
            HStack(spacing: 16) {
                Label(entry.statusLabel, systemImage: entry.isSuccess ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .font(.subheadline.bold())
                    .foregroundStyle(entry.isSuccess ? .green : .red)
                Text("\(entry.durationMs) ms")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(entry.date.formatted(date: .abbreviated, time: .standard))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal)
            .padding(.vertical, 10)
            .background(Color.secondary.opacity(0.1))

            Picker("", selection: $section) {
                Text("Request").tag(0)
                Text("Response").tag(1)
                Text("cURL").tag(2)
            }
            .pickerStyle(.segmented)
            .padding()

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    switch section {
                    case 0: requestSection
                    case 1: responseSection
                    default: curlSection
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 32)
            }
        }
        .navigationTitle("\(entry.method) \(URL(string: entry.url)?.path ?? "")")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                ShareLink(
                    item: shareText,
                    preview: SharePreview("\(entry.method) \(entry.statusLabel)", image: Image(systemName: "network"))
                ) {
                    Image(systemName: "square.and.arrow.up")
                }
            }
        }
    }

    // MARK: Sections

    private var requestSection: some View {
        Group {
            InfoBlock(title: "URL", content: entry.url)
            InfoBlock(title: "Method", content: entry.method)
            if !entry.requestHeaders.isEmpty {
                InfoBlock(
                    title: "Headers",
                    content: entry.requestHeaders.sorted { $0.key < $1.key }
                        .map { "\($0.key): \($0.value)" }.joined(separator: "\n")
                )
            }
            if let body = entry.requestBody, !body.isEmpty {
                InfoBlock(title: "Body", content: prettyJson(body) ?? body, mono: true)
            }
        }
    }

    private var responseSection: some View {
        Group {
            InfoBlock(title: "Status", content: entry.statusLabel,
                      tint: entry.isSuccess ? .green : .red)
            InfoBlock(title: "Duration", content: "\(entry.durationMs) ms")
            if let error = entry.error {
                InfoBlock(title: "Error", content: error, tint: .red)
            }
            if !entry.responseHeaders.isEmpty {
                InfoBlock(
                    title: "Headers",
                    content: entry.responseHeaders.sorted { $0.key < $1.key }
                        .map { "\($0.key): \($0.value)" }.joined(separator: "\n")
                )
            }
            if let body = entry.responseBody, !body.isEmpty {
                InfoBlock(title: "Body", content: prettyJson(body) ?? body, mono: true)
            }
        }
    }

    private var curlSection: some View {
        InfoBlock(title: "cURL", content: entry.curlCommand, mono: true)
    }

    // MARK: Share text

    private var shareText: String {
        """
        \(entry.method) \(entry.url)
        Status: \(entry.statusLabel) | \(entry.durationMs)ms
        Date: \(entry.date.formatted())

        --- REQUEST HEADERS ---
        \(entry.requestHeaders.sorted { $0.key < $1.key }.map { "\($0.key): \($0.value)" }.joined(separator: "\n"))

        --- REQUEST BODY ---
        \(entry.requestBody ?? "(empty)")

        --- RESPONSE BODY ---
        \(entry.responseBody ?? "(empty)")

        --- cURL ---
        \(entry.curlCommand)
        """
    }
}
