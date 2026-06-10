import SwiftUI

// MARK: - WireTapExportSheet (TRACER-003 filtered "Copy for AI")

/// A small sheet to scope the LLM export before copying: pick streams, BLE/NFC event
/// types, and an optional search term. Defaults to "everything", so hitting Copy with
/// no changes gives the full session.
struct WireTapExportSheet: View {
    @Environment(\.dismiss) private var dismiss

    @State private var includeNetwork = true
    @State private var includeBle = true
    @State private var includeNfc = true
    @State private var bleTypes: Set<BleEventType> = []   // empty == all
    @State private var nfcTypes: Set<NfcEventType> = []   // empty == all
    @State private var searchText = ""

    /// Called with the assembled options when the user taps Copy.
    let onCopy: (LLMExportOptions) -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section("Streams") {
                    Toggle("Network", isOn: $includeNetwork)
                    Toggle("BLE", isOn: $includeBle)
                    Toggle("NFC", isOn: $includeNfc)
                }

                Section("Search (optional)") {
                    TextField("Only events containing…", text: $searchText)
                        .disableAutocorrection(true)
                }

                if includeBle {
                    Section("BLE event types — none = all") {
                        chips(BleEventType.allCases, selected: $bleTypes) { $0.rawValue }
                    }
                }
                if includeNfc {
                    Section("NFC event types — none = all") {
                        chips(NfcEventType.allCases, selected: $nfcTypes) { $0.rawValue }
                    }
                }
            }
            .navigationTitle("Copy for AI")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Copy") { onCopy(buildOptions()); dismiss() }
                }
            }
        }
    }

    private func buildOptions() -> LLMExportOptions {
        var options = LLMExportOptions()
        var include: Set<LLMExportOptions.Stream> = []
        if includeNetwork { include.insert(.network) }
        if includeBle { include.insert(.ble) }
        if includeNfc { include.insert(.nfc) }
        options.include = include.isEmpty ? Set(LLMExportOptions.Stream.allCases) : include
        options.bleTypes = bleTypes.isEmpty ? nil : bleTypes
        options.nfcTypes = nfcTypes.isEmpty ? nil : nfcTypes
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        options.searchText = trimmed.isEmpty ? nil : trimmed
        return options
    }

    @ViewBuilder
    private func chips<T: Hashable>(_ all: [T], selected: Binding<Set<T>>, label: @escaping (T) -> String) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), spacing: 8)], alignment: .leading, spacing: 8) {
            ForEach(all, id: \.self) { item in
                let on = selected.wrappedValue.contains(item)
                Button {
                    if on { selected.wrappedValue.remove(item) } else { selected.wrappedValue.insert(item) }
                } label: {
                    Text(label(item))
                        .font(.caption)
                        .lineLimit(1)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .frame(maxWidth: .infinity)
                        .background(on ? Color.accentColor : Color.secondary.opacity(0.15))
                        .foregroundStyle(on ? Color.white : Color.primary)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 4)
    }
}
