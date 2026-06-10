import SwiftUI

// MARK: - ConnectionLifecycleView (TRACER-006)

/// Shows each BLE connection attempt as a phase sequence with an outcome, so "how far
/// did it get and why did it stop" is visible at a glance.
public struct ConnectionLifecycleView: View {
    @ObservedObject private var store = WireTap.ble

    public init() {}

    public var body: some View {
        let attempts = Array(store.connectionAttempts().reversed()) // newest first

        Group {
            if attempts.isEmpty {
                PlaceholderView(
                    title: "No Connections",
                    systemImage: "point.3.connected.trianglepath.dotted",
                    description: "Connection attempts appear here once BLE activity is captured."
                )
            } else {
                List {
                    ForEach(attempts) { attempt in
                        Section {
                            ForEach(Array(attempt.steps.enumerated()), id: \.offset) { _, step in
                                StepRow(step: step)
                            }
                        } header: {
                            AttemptHeader(attempt: attempt)
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle("Lifecycle")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}

// MARK: - Header

private struct AttemptHeader: View {
    let attempt: ConnectionAttempt

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: attempt.outcome.symbol)
                .foregroundStyle(attempt.outcome.color)
            VStack(alignment: .leading, spacing: 1) {
                Text(attempt.device ?? "Unknown device")
                    .font(.subheadline.weight(.semibold))
                Text(attempt.outcome.label)
                    .font(.caption)
                    .foregroundStyle(attempt.outcome.color)
            }
            Spacer()
            if let d = attempt.duration {
                Text(String(format: "%.2fs", d))
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
        }
        .textCase(nil)
        .padding(.vertical, 4)
    }
}

// MARK: - Step row

private struct StepRow: View {
    let step: LifecycleStep

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: step.phase.symbol)
                .font(.caption)
                .foregroundStyle(step.phase.color)
                .frame(width: 18)
            Text(step.phase.label)
                .font(.callout)
            if let detail = step.detail, !detail.isEmpty {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
        }
    }
}

// MARK: - Display mapping

private extension ConnectionOutcome {
    var label: String {
        switch self {
        case .inProgress:                 return "In progress"
        case .streaming:                  return "Streaming"
        case let .disconnected(reason):   return reason.map { "Disconnected — \($0)" } ?? "Disconnected"
        case let .failed(phase, reason):  return "Failed at \(phase.label)" + (reason.map { " — \($0)" } ?? "")
        }
    }
    var color: Color {
        switch self {
        case .inProgress:   return .secondary
        case .streaming:    return .green
        case .disconnected: return .orange
        case .failed:       return .red
        }
    }
    var symbol: String {
        switch self {
        case .inProgress:   return "ellipsis.circle"
        case .streaming:    return "checkmark.circle.fill"
        case .disconnected: return "xmark.circle"
        case .failed:       return "exclamationmark.triangle.fill"
        }
    }
}

private extension LifecyclePhase {
    var label: String {
        switch self {
        case .connecting:  return "Connecting"
        case .connected:   return "Connected"
        case .services:    return "Services discovered"
        case .mtu:         return "MTU negotiated"
        case .pairing:     return "Pairing"
        case .paired:      return "Paired"
        case .pairFailed:  return "Pairing failed"
        case .authStarted: return "Auth started"
        case .authed:      return "Authenticated"
        case .authFailed:  return "Auth failed"
        case .streaming:   return "Streaming"
        case .error:       return "Error"
        case .disconnected: return "Disconnected"
        }
    }
    var color: Color {
        switch self {
        case .paired, .authed, .connected, .streaming: return .green
        case .pairFailed, .authFailed, .error:         return .red
        case .disconnected:                            return .orange
        default:                                       return .secondary
        }
    }
    var symbol: String {
        switch self {
        case .pairFailed, .authFailed, .error: return "xmark.circle.fill"
        case .paired, .authed, .connected, .streaming: return "checkmark.circle.fill"
        case .disconnected: return "bolt.horizontal.circle"
        default: return "circle"
        }
    }
}
