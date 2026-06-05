# Feature Spec: Unified Session Export / Import

**Spec ID**: TRACER-002
**Component**: WireTap (core + UI)
**Author**: Poshan Karki
**Status**: Implemented
**Created**: 2026-06-04
**Last updated**: 2026-06-04
**Depends on**: TRACER-001 (Codable entries, persistence)
**Unlocks**: TRACER-003 (reuses serialization), TRACER-004 (MCP reads this file), TRACER-008 (diff)

---

## 1. Summary

A developer hits a bug — a failed pairing, a 500, a malformed NDEF record — and
wants to hand the *whole picture* to a teammate, a bug tracker, or (TRACER-003/004)
an AI agent. Today the share sheet only shares a single entry's text.

This spec defines the **`.wiretapsession` file**: one self-contained JSON document
bundling **all three streams (network, BLE, NFC) merged into a single, time-ordered
timeline**, plus capture metadata (app, OS, device, time range, schema version).
The inspector can **export** the current capture to this file and **import** one for
read-only inspection offline.

The unified, cross-radio timeline is the artifact WireTap can produce that no
network-only competitor can — it is the foundation for the AI layer.

---

## 2. Public API Surface

```swift
public struct WireTapSession: Codable, Sendable {
    public let schemaVersion: Int            // current: 1
    public let exportedAt: Date
    public let app: AppInfo                   // bundleId, version, build
    public let environment: EnvInfo           // os, osVersion, device model, locale
    public let range: ClosedRange<Date>?      // first…last event time, nil if empty
    public let network: [NetworkEntry]
    public let ble: [BleEntry]
    public let nfc: [NfcEntry]
}

public struct TimelineItem: Sendable {        // unified view, derived not stored
    public enum Kind { case network, ble, nfc }
    public let timestamp: Date
    public let kind: Kind
    public let summary: String
    public let entryId: UUID
}

extension WireTap {
    /// Snapshot all stores into a session value.
    public static func makeSession() -> WireTapSession
    /// Encode a session to pretty JSON `Data` (UTF-8).
    public static func exportSessionData() throws -> Data
    /// Merge all three streams into one ascending-time timeline.
    public static func timeline() -> [TimelineItem]
    /// Decode a `.wiretapsession` for read-only inspection.
    public static func importSession(_ data: Data) throws -> WireTapSession
}
```

| Symbol | Kind | Notes |
|--------|------|-------|
| `WireTapSession` | new public struct | The on-disk/share schema; `schemaVersion` gates forward-compat |
| `TimelineItem` | new public struct | Derived merge for the unified view; not persisted |
| `makeSession` / `exportSessionData` / `importSession` / `timeline` | new static funcs | Pure, main-actor snapshot |
| `AppInfo` / `EnvInfo` | new public structs | Captured at export time from `Bundle`/`ProcessInfo`/`UIDevice` |

**File**: UTI `com.wiretap.session`, extension `.wiretapsession`, JSON, UTF-8.
**Requirement**: every `*Entry` must carry a stable `id: UUID` and a `timestamp: Date`
(add if missing — needed for ordering, dedup, and TimelineItem mapping).

---

## 3. UI States

| State | When | UI shows | Actions |
|-------|------|----------|---------|
| Export available | Any tab, ≥1 entry captured | Toolbar "Export Session" (share icon) | Share `.wiretapsession` via share sheet |
| Export empty | No entries in any store | Export action disabled | — |
| Timeline tab | New unified view | All 3 streams merged, ascending time, color-coded by kind, filterable by kind | Tap → existing per-entry detail |
| Importing | User opens a `.wiretapsession` | Read-only banner ("Imported session — capture paused") + populated tabs | Close → return to live |
| Import failure | Bad/old-schema file | Error card with reason | Dismiss |

---

## 4. Constraints & Invariants

- [ ] Export reflects a **consistent snapshot** taken on the main actor (no torn reads).
- [ ] **Redaction already applied** — export serializes already-redacted entries; export adds no new secret path.
- [ ] Timeline ordering is **stable & deterministic**: ascending `timestamp`, ties broken by `kind` then `id`.
- [ ] Import is **read-only**: it must not mutate or merge into live stores.
- [ ] `schemaVersion` mismatch is handled explicitly (load newer minor, reject unknown major with a clear message).
- [ ] No third-party dependencies.

---

## 5. Acceptance Criteria

> `Tests/WireTapTests/SessionExportSpec.swift`.

### AC-1: Export bundles all three streams
**Given** 2 network, 3 BLE, 1 NFC entries captured
**When** `exportSessionData()` is encoded then decoded back via `importSession`
**Then** the session contains exactly those 2/3/1 entries with fields intact and a non-nil `range`
**Automated**: `SessionExportSpec.test_AC1_exportRoundTripsAllStreams`

### AC-2: Unified timeline is time-ordered
**Given** entries interleaved across streams with known timestamps
**When** `timeline()` is built
**Then** items are strictly ascending by timestamp, ties broken deterministically by kind then id
**Automated**: `SessionExportSpec.test_AC2_timelineIsDeterministicallyOrdered`

### AC-3: Empty capture exports a valid, empty session
**Given** all stores empty
**When** `makeSession()` is called
**Then** it returns a valid session with empty arrays and `range == nil` (no crash)
**Automated**: `SessionExportSpec.test_AC3_emptySessionIsValid`

### AC-4: Redaction holds through export
**Given** a network entry with a redacted Authorization header
**When** the session is encoded to `Data`
**Then** the bytes contain `[redacted]` and never the secret token
**Automated**: `SessionExportSpec.test_AC4_exportStaysRedacted`

### AC-5: Import is read-only
**Given** live stores with entries
**When** a different session file is imported
**Then** `importSession` returns the imported value AND the live stores are unchanged
**Automated**: `SessionExportSpec.test_AC5_importDoesNotMutateLiveStores`

### AC-6: Schema-version handling
**Given** a file with `schemaVersion` greater than supported major
**When** imported
**Then** it throws `WireTapSessionError.unsupportedSchema(version:)` with the version, no crash
**Automated**: `SessionExportSpec.test_AC6_rejectsUnsupportedSchema`

### AC-7: Metadata is captured
**Given** an export on a known bundle/OS
**When** the session is produced
**Then** `app.bundleId`, `app.version`, `environment.osVersion` are populated (non-empty)
**Automated**: `SessionExportSpec.test_AC7_metadataPopulated`

---

## 6. Error Cases

| Error | Source | User sees | Recovery |
|-------|--------|-----------|----------|
| Encode failure | `JSONEncoder` | "Could not export session" toast | Retry |
| Import decode failure | malformed JSON | Error card: "Not a valid WireTap session" | Dismiss |
| Unsupported schema major | newer file | Error card naming the version | Update WireTap |
| Share sheet cancelled | user | No-op | — |

---

## 7. Data Model Changes

| Model | Change | Reason |
|-------|--------|--------|
| `NetworkEntry` / `BleEntry` / `NfcEntry` | add stable `id: UUID` + `timestamp: Date` if absent | Ordering, dedup, TimelineItem |
| `WireTapSession`, `TimelineItem`, `AppInfo`, `EnvInfo` | new public types | Export schema + unified view |
| `WireTapSessionError` | new public error enum | `unsupportedSchema`, `decodeFailed` |
| New `TimelineView` (SwiftUI) | new file | 4th inspector tab |

---

## 8. Out of Scope

- LLM-shaped/compact export (that is TRACER-003; this is the lossless human/tool format).
- MCP serving (TRACER-004).
- Editing/replaying captured traffic (Fiddler-style modify-and-replay) — future.
- Binary/compressed container — plain JSON for inspectability; revisit if size hurts.

---

## 9. Open Questions

| # | Question | Resolution |
|---|----------|------------|
| 1 | Add per-entry `correlationId` now for TRACER-007? | Yes — add the optional field now (cheap), populate later. |
| 2 | Gzip large sessions on share? | Defer; measure real sizes after TRACER-001 lands. |

---

## 10. Test Coverage Checklist

- [x] AC-1 round-trips all streams
- [x] AC-2 deterministic timeline order
- [x] AC-3 empty session valid
- [x] AC-4 redaction holds
- [x] AC-5 import read-only
- [x] AC-6 schema-version rejection
- [x] AC-7 metadata populated
- [x] Share-sheet wiring — `WireTapView` toolbar → "Export Session…" (iOS share sheet via
      `WireTapShareSheet`; pasteboard fallback on macOS) + "Copy for AI" (TRACER-003)
- [x] `TimelineView` inspector tab — new `.timeline` `WireTapTab`, cross-stream unified view
      with per-kind filter chips; included in `.all`

**Implemented in**: `Sources/WireTap/Core/SessionExport.swift` (`WireTapSession`, `AppInfo`,
`EnvInfo`, `NetworkRecord`/`BleRecord`/`NfcRecord`, `TimelineItem`, `WireTapSessionError`,
`WireTap.makeSession/exportSessionData/importSession/timeline`); UI in
`Sources/WireTap/Views/TimelineView.swift`, `Views/Shared/WireTapShare.swift`, and the
`.timeline` tab + export menu in `Views/WireTapView.swift`. Tests:
`Tests/WireTapTests/SessionExportSpec.swift`. **Cross-validated**: a Swift-emitted
`.wiretapsession` parses correctly in the `wiretap-mcp` Node server, with secrets redacted.
UI verified by cross-platform compile (manual on-device check pending).
