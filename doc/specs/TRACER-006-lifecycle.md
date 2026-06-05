# Feature Spec: Connection Lifecycle Timeline

**Spec ID**: TRACER-006
**Component**: WireTap (core derivation + UI)
**Author**: Poshan Karki
**Status**: Implemented
**Created**: 2026-06-05
**Last updated**: 2026-06-05
**Depends on**: existing `BleEntry` capture (no new capture)

---

## 1. Summary

The BLE tab is a flat event log. When a connection fails, you have to mentally reconstruct
how far it got — `connecting → connected → services → pair → auth → streaming` — and where it
stopped. This spec derives that **per-attempt lifecycle** from the existing `BleEntry` stream
and shows it as a compact sequence with an outcome, so the "why did reconnect fail" class of
bug (a recurring one for device teams) is visible at a glance.

Pure derivation — no new capture, no export/contract change, no Node impact.

---

## 2. Public API Surface

```swift
public enum LifecyclePhase: String, Sendable {
    case connecting, connected, services, mtu, pairing, paired, pairFailed
    case authStarted, authed, authFailed, streaming, error, disconnected
}

public struct LifecycleStep: Sendable, Equatable {
    public let phase: LifecyclePhase
    public let date: Date
    public let detail: String?       // error ?? detail of the source event
}

public enum ConnectionOutcome: Sendable, Equatable {
    case inProgress
    case streaming
    case disconnected(reason: String?)
    case failed(phase: LifecyclePhase, reason: String?)
}

public struct ConnectionAttempt: Identifiable, Sendable {
    public let id: UUID
    public let device: String?
    public let start: Date
    public let end: Date?
    public let steps: [LifecycleStep]
    public let outcome: ConnectionOutcome
    public var duration: TimeInterval? { end.map { $0.timeIntervalSince(start) } }
}

public extension BleStore {
    /// Group the captured BLE events into per-connection attempts with an outcome.
    func connectionAttempts() -> [ConnectionAttempt]
}
```

**Derivation:** walk BLE entries chronologically; open an attempt on
`connecting`/`reconnecting`/`connected` (tolerate a missing `connecting`); map lifecycle-relevant
event types to a step (read/write/rssi/info are ignored); the first notification/indication marks
`streaming`; `disconnected` closes the attempt. Outcome priority: `authFailed` → `pairFailed` →
`disconnected` → `streaming` → `inProgress`.

---

## 3. UI

A **Connection lifecycle** screen reached from the top of the BLE tab. Each attempt shows the
device, an outcome badge (green streaming / red failed / grey in-progress / orange disconnected),
duration, and the ordered steps with per-phase pass/fail icons. UI is manual-verified.

---

## 4. Constraints & Invariants

- [ ] **Derivation only** — reads `BleStore.entries`; no new capture, no stored state.
- [ ] **Deterministic & order-stable** — chronological by `date`.
- [ ] **Tolerant** — handles missing `connecting`, multiple attempts, and an open (in-progress) attempt.
- [ ] **No export/Node impact** — does not touch `.wiretapsession`, the LLM render, or the golden.

---

## 5. Acceptance Criteria

> `Tests/WireTapTests/ConnectionLifecycleSpec.swift`.

### AC-1: Happy path → streaming
**Given** connecting → connected → services → paired → authed → notification
**When** `connectionAttempts()` runs
**Then** one attempt, `outcome == .streaming`, steps in phase order ending at `.streaming`
**Automated**: `ConnectionLifecycleSpec.test_AC1_happyPathStreaming`

### AC-2: Auth failure → failed(auth)
**Given** connecting → connected → authStarted → authFailed("stale cert") → disconnected
**When** derived
**Then** `outcome == .failed(phase: .authFailed, reason: "stale cert")`
**Automated**: `ConnectionLifecycleSpec.test_AC2_authFailure`

### AC-3: Multiple attempts split
**Given** (connecting,connected,disconnected) then (connecting,connected,notification)
**When** derived
**Then** two attempts; first `.disconnected`, second `.streaming`
**Automated**: `ConnectionLifecycleSpec.test_AC3_multipleAttempts`

### AC-4: Open attempt → inProgress
**Given** connecting → connected with no terminal event
**When** derived
**Then** one attempt, `outcome == .inProgress`, `end == nil`, `duration == nil`
**Automated**: `ConnectionLifecycleSpec.test_AC4_inProgress`

### AC-5: Duration computed
**Given** an attempt spanning known timestamps
**When** derived
**Then** `duration` equals end − start
**Automated**: `ConnectionLifecycleSpec.test_AC5_duration`

---

## 6. Out of Scope

- Cross-radio correlation (NFC tap → this BLE attempt → network) — that is TRACER-007.
- Adding the lifecycle summary to the LLM export — possible later; kept out to avoid Node/golden churn.

---

## 7. Test Coverage Checklist

- [x] AC-1 happy path
- [x] AC-2 auth failure
- [x] AC-3 multiple attempts
- [x] AC-4 in-progress
- [x] AC-5 duration

**Implemented in**: `Core/ConnectionLifecycle.swift` (`LifecyclePhase`, `LifecycleStep`,
`ConnectionOutcome`, `ConnectionAttempt`, `BleStore.connectionAttempts()`); UI in
`Views/BLE/ConnectionLifecycleView.swift`, reachable from a link in `BleLogView`. Tests:
`Tests/WireTapTests/ConnectionLifecycleSpec.swift` (5). No export/Node/golden impact (derivation only).
