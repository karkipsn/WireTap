# Feature Spec: Session Diff

**Spec ID**: TRACER-008
**Component**: WireTap (core derivation + UI)
**Author**: Poshan Karki
**Status**: Implemented
**Created**: 2026-06-05
**Last updated**: 2026-06-05
**Depends on**: TRACER-002 (`WireTapSession`, `makeSession`)

---

## 1. Summary

"It paired fine yesterday, fails today" is answered fastest by **comparing a working capture to
a failing one**. This spec diffs two sessions and shows what diverged — e.g. the failing run is
*missing* `ble:authSuccess` and has an *extra* `ble:authFailed`, or the same request went `2xx` → `4xx`.

Because event ids and timestamps differ between runs, matching is by a **normalized signature**
(kind + meaningful key), count-aware. In-app it uses a **baseline snapshot** workflow — no file
pickers: snapshot a good run, reproduce the bad one, diff. Pure derivation; no export/Node impact.

---

## 2. Public API Surface

```swift
public struct EventSignature: Sendable, Hashable {
    public let kind: TimelineItem.Kind
    public let key: String   // e.g. "ble:authFailed", "net:POST https://… 4xx", "nfc:recordParsed"
}

public struct SessionDiff: Sendable {
    public let onlyInA: [EventSignature]   // in A, not B (count-aware surplus)
    public let onlyInB: [EventSignature]   // in B, not A
    public let common:  [EventSignature]   // shared (min multiplicity)
}

public extension WireTap {
    static func diff(_ a: WireTapSession, _ b: WireTapSession) -> SessionDiff

    /// In-memory baseline for the "good run vs current" workflow.
    static var baselineSession: WireTapSession? { get set }   // @MainActor
}
```

**Signatures:** BLE → `ble:<type>`; Network → `net:<method> <url> <statusClass>`
(`2xx/4xx/5xx/err/?`); NFC → `nfc:<type>`. Diff is a **count-aware multiset** difference:
surplus in A → `onlyInA`, surplus in B → `onlyInB`, shared min → `common`. Deterministic
(sorted by key).

---

## 3. UI

A **Session diff** screen from the Timeline tab:
- No baseline yet → a "Snapshot current as baseline" button (`baselineSession = makeSession()`).
- Baseline set → diff(baseline, current) with three sections — **Only in baseline** (red, "lost"),
  **Only in current** (green/orange, "new"), **Common** — plus "Re-snapshot" / "Clear baseline".
UI is manual-verified.

---

## 4. Constraints & Invariants

- [ ] **Derivation only** — `diff` is a pure function of two `WireTapSession` values.
- [ ] **Deterministic** — signature sets sorted by key; count-aware multiset semantics.
- [ ] **Identity** — diffing a session against itself yields empty `onlyInA`/`onlyInB`.
- [ ] **No export/Node impact.**

---

## 5. Acceptance Criteria

> `Tests/WireTapTests/SessionDiffSpec.swift`. Sessions built via `WireTap.makeSession()` snapshots.

### AC-1: Identical sessions → no differences
**Given** the same capture snapshotted twice
**When** diffed
**Then** `onlyInA` and `onlyInB` are empty; `common` holds the signatures
**Automated**: `SessionDiffSpec.test_AC1_identical`

### AC-2: Divergent BLE outcome
**Given** A ends `authSuccess`, B ends `authFailed`
**When** diffed
**Then** `onlyInA` contains `ble:authSuccess`, `onlyInB` contains `ble:authFailed`
**Automated**: `SessionDiffSpec.test_AC2_bleOutcome`

### AC-3: Network status class change
**Given** A has `POST url` → 200, B has `POST url` → 401
**When** diffed
**Then** `onlyInA` has the `…2xx` signature, `onlyInB` the `…4xx`
**Automated**: `SessionDiffSpec.test_AC3_networkStatusClass`

### AC-4: Count-aware
**Given** A has 1 `connecting`, B has 3 `connecting`
**When** diffed
**Then** `onlyInB` contains `ble:connecting` exactly twice
**Automated**: `SessionDiffSpec.test_AC4_countAware`

### AC-5: Common events
**Given** both sessions contain `connected`
**When** diffed
**Then** `common` contains `ble:connected`
**Automated**: `SessionDiffSpec.test_AC5_common`

---

## 6. Out of Scope

- Ordered/LCS diff (multiset signature diff answers the "what changed" question for this flow).
- Diffing arbitrary files via a document picker (baseline snapshot covers the in-app case;
  file import can layer on TRACER-002's `importSession` later).

---

## 7. Test Coverage Checklist

- [x] AC-1 identical
- [x] AC-2 BLE outcome
- [x] AC-3 network status class
- [x] AC-4 count-aware
- [x] AC-5 common

**Implemented in**: `Core/SessionDiff.swift` (`EventSignature`, `SessionDiff`, `WireTap.diff(_:_:)`,
`WireTap.baselineSession`); UI in `Views/SessionDiffView.swift`, reachable from `TimelineView`.
Tests: `Tests/WireTapTests/SessionDiffSpec.swift` (5). BLE signatures use the event-type case name
(e.g. `ble:authSuccess`). No export/Node/golden impact.
