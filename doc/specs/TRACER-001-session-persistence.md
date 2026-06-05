# Feature Spec: Session Persistence

**Spec ID**: TRACER-001
**Component**: WireTap (core)
**Author**: Poshan Karki
**Status**: Implemented
**Created**: 2026-06-04
**Last updated**: 2026-06-04
**Depends on**: —
**Unlocks**: TRACER-002, TRACER-008

---

## 1. Summary

Today all three stores (`NetworkStore`, `BleStore`, `NfcStore`) hold entries only
in memory (`@Published [...]`, capped by `maxEntries`). Everything is lost on app
relaunch. This is the single biggest gap versus Pulse, whose persistent store is
its defining QA feature.

This spec adds **opt-in durable persistence**: captured entries are written to disk
and reloaded on next launch, so a developer or tester can inspect — and later export
(TRACER-002) — traffic from a previous run, including the run that just crashed.

Persistence is **off by default** (preserving today's in-memory, zero-IO behavior)
and **DEBUG-oriented**. Zero third-party dependencies: `Codable` + a JSONL file per
store, written off the main actor.

---

## 2. Public API Surface

> WireTap is a library; this section replaces the template's BLE/NFC mapping.

```swift
public enum WireTapStorage: Sendable {
    case inMemory                                   // default — today's behavior
    case disk(directory: URL? = nil, fileCap: Int = 5_000)
}

extension WireTap {
    /// Configure once at startup, before the first capture. Default `.inMemory`.
    public static func configure(storage: WireTapStorage)
}
```

| Symbol | Kind | Notes |
|--------|------|-------|
| `WireTapStorage` | new public enum | `.inMemory` (default) or `.disk` |
| `WireTap.configure(storage:)` | new static func | Idempotent before first capture; no-op + warning if called after |
| `NetworkEntry` / `BleEntry` / `NfcEntry` | conform to `Codable` | Required for serialization; `hexString`/`asciiString` stay computed (not encoded) |
| each store's `clear()` | behavior change | Also truncates the on-disk file when `.disk` |

**Storage location** (when `directory` is nil): `<AppSupport>/WireTap/` — created lazily.
**Files**: `network.jsonl`, `ble.jsonl`, `nfc.jsonl` — one JSON object per line (append-friendly, partial-read tolerant).

---

## 3. UI States

No new screens. Existing inspector tabs gain reloaded-from-disk entries on launch.

| State | When | UI shows |
|-------|------|----------|
| Cold start, `.inMemory` | Default | Empty stores (unchanged from today) |
| Cold start, `.disk` | Persistence on, prior data exists | Tabs pre-populated with persisted entries, newest first |
| Cold start, `.disk`, corrupt line | A JSONL line fails to decode | That line is skipped; valid lines load; a single `info` entry notes N skipped |
| After `clear()` | Any | Tab empty AND on-disk file truncated |

---

## 4. Constraints & Invariants

- [ ] `.inMemory` remains the default — existing integrators see **no behavior change**.
- [ ] Disk writes happen **off the main actor**; capturing an entry never blocks UI.
- [ ] On-disk entry count is bounded by `fileCap` (rolling: oldest lines dropped), independent of each store's in-memory `maxEntries`.
- [ ] **Redaction runs before persistence** — an unredacted `Authorization` header (or any TRACER-010 rule) must never reach disk.
- [ ] Persistence is intended for DEBUG builds; the API exists in all builds but writes nothing under `.inMemory`.
- [ ] No third-party dependencies; `Foundation` only.

---

## 5. Acceptance Criteria

> Each AC ⇄ one test in `Tests/WireTapTests/SessionPersistenceSpec.swift`. Disk tests
> use a temporary `directory:` URL and delete it in `tearDown`.

### AC-1: Default stays in-memory
**Given** `WireTap.configure` is never called
**When** entries are recorded and a fresh store is constructed from the same directory
**Then** nothing is read from or written to disk; behavior is identical to today
**Automated**: `SessionPersistenceSpec.test_AC1_defaultIsInMemory_noDiskIO`

### AC-2: Entries survive a simulated relaunch
**Given** `.disk(directory: tmp)` is configured
**When** 3 network + 2 BLE + 1 NFC entries are recorded, then a new store set is created pointed at `tmp` (simulating relaunch)
**Then** all 6 entries reload, newest-first, with fields intact
**Automated**: `SessionPersistenceSpec.test_AC2_entriesReloadAfterRelaunch`

### AC-3: File cap is enforced
**Given** `.disk(fileCap: 100)`
**When** 150 entries are recorded
**Then** the on-disk file contains exactly 100 lines (the 100 newest) after a relaunch
**Automated**: `SessionPersistenceSpec.test_AC3_fileCapRollsOldest`

### AC-4: clear() truncates disk
**Given** `.disk` with persisted entries
**When** `WireTap.ble.clear()` is called
**Then** the in-memory store is empty AND `ble.jsonl` is 0 bytes; a subsequent relaunch loads nothing
**Automated**: `SessionPersistenceSpec.test_AC4_clearTruncatesDiskFile`

### AC-5: Redaction precedes persistence
**Given** `.disk` and a network entry whose request has `Authorization: Bearer secret`
**When** the entry is persisted and the raw file bytes are read back
**Then** the file contains `[redacted]` and never the literal `secret`
**Automated**: `SessionPersistenceSpec.test_AC5_redactedBeforeDisk`

### AC-6: Corrupt line tolerance
**Given** a `ble.jsonl` whose 2nd line is invalid JSON
**When** the store loads at launch
**Then** the valid lines load, the bad line is skipped, no crash, and one `info` entry records the skip count
**Automated**: `SessionPersistenceSpec.test_AC6_corruptLineSkipped`

### AC-7: Capture never blocks the main actor
**Given** `.disk`
**When** 1,000 entries are recorded in a tight loop on the main actor
**Then** `record`/`log` return synchronously without awaiting disk IO (writes are dispatched), asserted via a timing/seam check
**Automated**: `SessionPersistenceSpec.test_AC7_captureDoesNotAwaitDiskIO`

---

## 6. Error Cases

| Error | Source | Behavior | Recovery |
|-------|--------|----------|----------|
| App Support dir not creatable | sandbox / disk full | Fall back to `.inMemory`, emit one `info` entry | Automatic |
| Write failure mid-session | disk full | Drop the write, keep in-memory entry, no crash | Next write retries |
| Decode failure on a line | corrupt file | Skip line (AC-6) | Automatic |
| `configure` called after first capture | misuse | No-op + `os_log` warning | Developer fixes call site |

---

## 7. Data Model Changes

| Model | Change | Reason |
|-------|--------|--------|
| `NetworkEntry` | `: Codable` | Serialize to JSONL |
| `BleEntry` | `: Codable`; ensure `BleEventType: Codable` | Serialize |
| `NfcEntry` | `: Codable`; ensure `NfcEventType: Codable` | Serialize |
| computed `hexString` / `asciiString` | excluded via `CodingKeys` | Derivable from `data`; don't bloat the file |
| new `PersistenceWriter` (internal) | new file | Off-actor JSONL append + rolling cap |

---

## 8. Out of Scope

- Encryption at rest (DEBUG tool; document the caveat instead).
- Cross-device sync / remote storage (cf. Pulse Pro — explicitly not a goal).
- A settings UI toggle (configured in code only).
- SQLite / Core Data (JSONL is sufficient and keeps zero-dep).

---

## 9. Open Questions

| # | Question | Resolution |
|---|----------|------------|
| 1 | Single rolling file vs. per-launch files? | Lean single rolling file + `fileCap`; per-launch deferred to TRACER-002 session bundles. |
| 2 | Should `.disk` auto-disable in RELEASE? | API present everywhere; recommend `#if DEBUG` at the call site per existing WireTap convention. |

---

## 10. Test Coverage Checklist

- [x] AC-1 default in-memory, no IO
- [x] AC-2 reload after relaunch
- [x] AC-3 file cap rolls oldest
- [x] AC-4 clear truncates disk
- [x] AC-5 redaction before disk
- [x] AC-6 corrupt line tolerance
- [x] AC-7 capture non-blocking
- [x] Fallback to in-memory on unwritable directory (PersistenceWriter `init?` returns nil → store stays in-memory)

**Implemented in**: `Sources/WireTap/Core/Persistence.swift` (`WireTapStorage`, `PersistenceWriter`,
`WireTapRedaction`), store wiring + `WireTap.configure(storage:)` in `Sources/WireTap/Core/WireTap.swift`,
Codable conformance on the three entry types/enums. Tests: `Tests/WireTapTests/SessionPersistenceSpec.swift`.
