import SwiftUI

// MARK: - SessionDiffView (TRACER-008)

/// Compare a baseline capture (a known-good run) against the current capture, so a
/// regression like "working pairing vs failing pairing" is visible as added/removed events.
public struct SessionDiffView: View {
    @ObservedObject private var network = WireTap.network
    @ObservedObject private var ble = WireTap.ble
    @ObservedObject private var nfc = WireTap.nfc

    @State private var baseline: WireTapSession? = WireTap.baselineSession

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Button(baseline == nil ? "Snapshot current as baseline" : "Re-snapshot") {
                    let snapshot = WireTap.makeSession()
                    WireTap.baselineSession = snapshot
                    baseline = snapshot
                }
                if baseline != nil {
                    Button("Clear") {
                        WireTap.baselineSession = nil
                        baseline = nil
                    }
                    .foregroundStyle(.red)
                }
                Spacer()
            }
            .font(.subheadline)
            .padding()

            Divider()

            if let baseline {
                let diff = WireTap.diff(baseline, WireTap.makeSession())
                List {
                    section("Only in baseline (lost)", diff.onlyInA, .red)
                    section("Only in current (new)", diff.onlyInB, .green)
                    section("Common", diff.common, .secondary)
                }
                .listStyle(.plain)
            } else {
                PlaceholderView(
                    title: "No Baseline",
                    systemImage: "arrow.left.arrow.right",
                    description: "Snapshot a good run as baseline, reproduce the issue, then compare."
                )
            }
        }
        .navigationTitle("Diff")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    @ViewBuilder
    private func section(_ title: String, _ sigs: [EventSignature], _ color: Color) -> some View {
        if !sigs.isEmpty {
            Section(title) {
                ForEach(grouped(sigs), id: \.key) { row in
                    HStack {
                        Text(row.key).font(.callout)
                        Spacer()
                        if row.count > 1 {
                            Text("×\(row.count)").font(.caption.monospaced()).foregroundStyle(.secondary)
                        }
                    }
                    .foregroundStyle(color)
                }
            }
        }
    }

    /// Collapse repeated signatures into (key, count), sorted by key.
    private func grouped(_ sigs: [EventSignature]) -> [(key: String, count: Int)] {
        Dictionary(grouping: sigs, by: { $0.key })
            .map { (key: $0.key, count: $0.value.count) }
            .sorted { $0.key < $1.key }
    }
}
