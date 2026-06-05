# Feature Spec: Cross-Radio Correlation

**Spec ID**: TRACER-007
**Component**: WireTap (core derivation + UI)
**Author**: Poshan Karki
**Status**: Implemented
**Created**: 2026-06-05
**Last updated**: 2026-06-05
**Depends on**: TRACER-002 (`timelineEntries`)

---

## 1. Summary

WireTap is the only inspector that captures NFC, BLE *and* network together — so it can show
what nothing else can: a single **episode** that stitches an NFC tap → the BLE connection it
triggered → the network calls that followed. This matches a typical tap-to-pair / tap-to-override
flow exactly ("I tapped, it connected, then the session sync 401'd").

Correlation is by **time-gap clustering** of the unified timeline: a run of cross-stream events
with no quiet gap larger than `maxGap` is one episode. Pure derivation — no `correlationId`
plumbing, no capture change, no export/Node impact.

---

## 2. Public API Surface

```swift
public enum EpisodeTrigger: String, Sendable { case nfcTap, bleConnect, network, other }

public struct CorrelatedEpisode: Identifiable, Sendable {
    public let id: UUID
    public let start: Date
    public let end: Date
    public let trigger: EpisodeTrigger     // classified from the first event
    public let nfcCount: Int
    public let bleCount: Int
    public let networkCount: Int
    public let items: [TimelineItem]        // the episode's events, ascending
    public var duration: TimeInterval { end.timeIntervalSince(start) }
}

public extension WireTap {
    /// Cluster the unified timeline into episodes separated by gaps > `maxGap` seconds.
    static func correlatedEpisodes(maxGap: TimeInterval = 60) -> [CorrelatedEpisode]
}
```

**Trigger classification** (first event's stream): `nfc → .nfcTap`, `ble → .bleConnect`,
`network → .network`, empty → n/a. Episodes are returned in ascending start order.

---

## 3. UI

A **Correlated episodes** screen reached from the Timeline tab: each episode is a section with
a trigger badge (📟 NFC tap / 🔵 BLE / 🌐 Network), the per-stream counts, duration, and its
ordered events. Lets you see one tap-to-pair-to-sync flow as a unit. UI is manual-verified.

---

## 4. Constraints & Invariants

- [ ] **Derivation only** — over `WireTap.timelineEntries()`; no new capture or stored state.
- [ ] **Deterministic** — ascending by time; gap rule is a strict `>` comparison.
- [ ] **No export/Node impact** — does not touch `.wiretapsession`, the LLM render, or the golden.
- [ ] **Bounded by data** — an empty capture yields no episodes (no crash).

---

## 5. Acceptance Criteria

> `Tests/WireTapTests/CorrelationSpec.swift`.

### AC-1: Gap clustering splits episodes
**Given** events at t=0,1,2 then t=200,201 with `maxGap=60`
**When** `correlatedEpisodes()` runs
**Then** two episodes: the first with the first 3 events, the second with the last 2
**Automated**: `CorrelationSpec.test_AC1_gapClustering`

### AC-2: Trigger classified from first event
**Given** an episode that begins with an NFC event, and another that begins with a BLE event
**When** derived
**Then** the first `trigger == .nfcTap`, the second `.bleConnect`
**Automated**: `CorrelationSpec.test_AC2_triggerClassification`

### AC-3: Per-stream counts
**Given** an episode with 1 nfc + 2 ble + 1 network event
**When** derived
**Then** `nfcCount==1, bleCount==2, networkCount==1`, `items.count==4`
**Automated**: `CorrelationSpec.test_AC3_counts`

### AC-4: Items ordered ascending, span streams
**Given** interleaved nfc/ble/network within one episode
**When** derived
**Then** `items` timestamps are non-decreasing and include all three kinds
**Automated**: `CorrelationSpec.test_AC4_ordering`

### AC-5: Duration & empty
**Given** an episode spanning known timestamps; and separately an empty capture
**When** derived
**Then** `duration == end − start`; empty capture → `[]`
**Automated**: `CorrelationSpec.test_AC5_durationAndEmpty`

---

## 6. Out of Scope

- Explicit `correlationId` propagation from the SDK (time-gap clustering is enough for the
  tap-to-pair flow; revisit only if episodes prove ambiguous).
- Adding episodes to the LLM export — deferred to avoid Node/golden churn.

---

## 7. Test Coverage Checklist

- [x] AC-1 gap clustering
- [x] AC-2 trigger classification
- [x] AC-3 counts
- [x] AC-4 ordering
- [x] AC-5 duration & empty

**Implemented in**: `Core/Correlation.swift` (`EpisodeTrigger`, `CorrelatedEpisode`,
`WireTap.correlatedEpisodes(maxGap:)`) over the shared `WireTap.timelineEntries()`; UI in
`Views/CorrelationView.swift`, reachable from a link in `TimelineView`. Tests:
`Tests/WireTapTests/CorrelationSpec.swift` (5). No export/Node/golden impact.
