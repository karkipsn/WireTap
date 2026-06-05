import SwiftUI

// MARK: - WireTapTab

/// The categories WireTap can display. An embedding app opts into the ones it captures,
/// in any combination — one, two, or all three — via an ordered array.
///
/// ```swift
/// WireTapView(tabs: [.network])              // one
/// WireTapView(tabs: [.ble, .nfc])            // two, in that tab order
/// WireTapView(tabs: .all)                    // unified Timeline + all three streams
/// WireTapView(tabs: WireTapTab.allCases)      // also all four
/// ```
public enum WireTapTab: String, CaseIterable, Sendable {
    case timeline
    case network
    case ble
    case nfc

    var title: String {
        switch self {
        case .timeline: return "Timeline"
        case .network:  return "Network"
        case .ble:      return "BLE"
        case .nfc:      return "NFC"
        }
    }

    var systemImage: String {
        switch self {
        case .timeline: return "list.bullet.rectangle"
        case .network:  return "network"
        case .ble:      return "dot.radiowaves.left.and.right"
        case .nfc:      return "sensor.tag.radiowaves.forward"
        }
    }
}

public extension Array where Element == WireTapTab {
    /// All categories, in canonical order — the unified Timeline plus each stream.
    static var all: [WireTapTab] { [.timeline, .network, .ble, .nfc] }
}

// MARK: - WireTapView

/// Root debug inspector. Drop inside a NavigationStack.
///
/// By default it shows **Network only** — the most universal signal. Apps that also
/// capture BLE / NFC opt those tabs in:
///
/// ```swift
/// NavigationStack { WireTapView() }                       // Network only (default)
/// NavigationStack { WireTapView(tabs: [.network, .ble]) } // Network + BLE
/// ```
///
/// With a single tab the segmented bar is hidden and that view fills the screen.
public struct WireTapView: View {
    @ObservedObject private var network = WireTap.network
    @ObservedObject private var ble = WireTap.ble
    @ObservedObject private var nfc = WireTap.nfc

    private let tabs: [WireTapTab]
    @State private var selection: WireTapTab
    @State private var shareItem: ShareItem?
    @State private var showExportSheet = false

    /// Wraps the export file URL so it can drive a `.sheet(item:)`.
    private struct ShareItem: Identifiable {
        let id = UUID()
        let url: URL
    }

    /// - Parameter tabs: Categories to show, in order. Duplicates are removed (first
    ///   occurrence wins); an empty array falls back to `[.network]`.
    public init(tabs: [WireTapTab] = [.network]) {
        var seen = Set<WireTapTab>()
        let unique = tabs.filter { seen.insert($0).inserted }
        let resolved = unique.isEmpty ? [.network] : unique
        self.tabs = resolved
        _selection = State(initialValue: resolved[0])
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Tab bar only when there's more than one category.
            if tabs.count > 1 {
                HStack(spacing: 0) {
                    ForEach(tabs, id: \.self) { tab in
                        TabButton(
                            title: tab.title,
                            systemImage: tab.systemImage,
                            badge: badge(for: tab),
                            isSelected: selection == tab
                        ) { selection = tab }
                    }
                }
                .padding(.horizontal)
                .padding(.top, 8)

                Divider()
            }

            content(for: tabs.count > 1 ? selection : tabs[0])
        }
        .navigationTitle("WireTap")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button { showExportSheet = true } label: {
                        Label("Copy for AI…", systemImage: "sparkles")
                    }
                    Button { exportSession() } label: {
                        Label("Export Session…", systemImage: "square.and.arrow.up")
                    }
                    Divider()
                    Button(role: .destructive) { clearShown() } label: {
                        Label("Clear", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .disabled(allEmpty)
            }
        }
        .sheet(isPresented: $showExportSheet) {
            WireTapExportSheet { options in
                WireTapPasteboard.copy(WireTap.exportForLLM(options))
            }
        }
        #if canImport(UIKit)
        .sheet(item: $shareItem) { item in
            WireTapShareSheet(items: [item.url])
        }
        #endif
    }

    @ViewBuilder
    private func content(for tab: WireTapTab) -> some View {
        switch tab {
        case .timeline: TimelineView()
        case .network:  NetworkListView()
        case .ble:      BleLogView()
        case .nfc:      NfcLogView()
        }
    }

    private func badge(for tab: WireTapTab) -> Int {
        switch tab {
        case .timeline: return network.entries.count + ble.entries.count + nfc.entries.count
        case .network:  return network.entries.count
        case .ble:      return ble.entries.count
        case .nfc:      return nfc.entries.count
        }
    }

    private var allEmpty: Bool {
        network.entries.isEmpty && ble.entries.isEmpty && nfc.entries.isEmpty
    }

    /// Clears only the categories this inspector is showing (Timeline clears all).
    private func clearShown() {
        for tab in tabs {
            switch tab {
            case .timeline: WireTap.clearAll()
            case .network:  WireTap.network.clear()
            case .ble:      WireTap.ble.clear()
            case .nfc:      WireTap.nfc.clear()
            }
        }
    }

    // MARK: Export (TRACER-002 / TRACER-003)

    /// Write a `.wiretapsession` bundle (TRACER-002) and present the share sheet (iOS).
    /// On platforms without a share sheet, the session JSON is copied to the pasteboard.
    private func exportSession() {
        guard let data = try? WireTap.exportSessionData() else { return }
        #if canImport(UIKit)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("wiretap-\(Int(Date().timeIntervalSince1970)).wiretapsession")
        guard (try? data.write(to: url)) != nil else { return }
        shareItem = ShareItem(url: url)
        #else
        WireTapPasteboard.copy(String(decoding: data, as: UTF8.self))
        #endif
    }
}

// MARK: - Tab button

private struct TabButton: View {
    let title: String
    let systemImage: String
    let badge: Int
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                Text(title)
                    .fontWeight(isSelected ? .semibold : .regular)
                if badge > 0 {
                    Text("\(badge)")
                        .font(.caption2.bold())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(isSelected ? Color.accentColor : Color.secondary)
                        .clipShape(Capsule())
                }
            }
            .font(.subheadline)
            .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .overlay(alignment: .bottom) {
                if isSelected {
                    Rectangle()
                        .frame(height: 2)
                        .foregroundStyle(Color.accentColor)
                }
            }
        }
        .buttonStyle(.plain)
    }
}
