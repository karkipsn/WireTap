# Feature Spec: LLM-Optimized Export

**Spec ID**: TRACER-003
**Component**: WireTap (core + UI)
**Author**: Poshan Karki
**Status**: Implemented
**Created**: 2026-06-04
**Last updated**: 2026-06-04
**Depends on**: TRACER-002 (session snapshot + timeline)
**Unlocks**: TRACER-004 (MCP server emits this format), TRACER-012 (in-app explain)

---

## 1. Summary

The `.wiretapsession` file (TRACER-002) is lossless and human/tool-friendly, but it
is **not** what you want to hand an AI coding agent: it is verbose, contains raw
binary blobs, and has no orientation text. Pasting it into Cursor/Claude Code burns
tokens and confuses the model.

This spec adds a **second, LLM-optimized rendering** of the same snapshot: a compact,
deterministic, **self-describing** document (Markdown with fenced JSONL, or pure
JSONL) sized for an agent's context window. It opens with a short schema preamble so
any model understands the fields without prior knowledge, truncates large payloads
with explicit markers, and is fully redacted.

This is the cheapest, highest-leverage AI feature: a **"Copy as AI context"** button
delivers 80% of the MCP server's value in a fraction of the work, and the MCP server
(TRACER-004) reuses this exact formatter.

---

## 2. Public API Surface

```swift
public struct LLMExportOptions: Sendable {
    public var format: Format = .markdown          // .markdown | .jsonl
    public var include: Set<Stream> = .all         // .network/.ble/.nfc
    public var maxPayloadBytes: Int = 256          // per-entry hex/body cap before truncation
    public var maxEntriesPerStream: Int = 200      // newest-first cap to bound tokens
    public var includeSchemaPreamble: Bool = true
    public enum Format: Sendable { case markdown, jsonl }
    public enum Stream: CaseIterable, Sendable { case network, ble, nfc }
}

extension WireTap {
    /// Render the current capture as an LLM-ingestible string.
    public static func exportForLLM(_ options: LLMExportOptions = .init()) -> String
    /// Render an already-captured session (e.g. imported) for an agent.
    public static func exportForLLM(_ session: WireTapSession,
                                    options: LLMExportOptions = .init()) -> String
}
```

| Symbol | Kind | Notes |
|--------|------|-------|
| `LLMExportOptions` | new public struct | Token-budget & content controls |
| `exportForLLM(...)` | new static funcs | Pure; deterministic for a fixed snapshot |

**Output (markdown format), shape:**

```
# WireTap session — connected-device runtime trace
Schema: each line under a stream is one event. Fields:
  net:  ts | method | url | status | durMs | err
  ble:  ts | type | uuid | device | hex(<=NB) | detail | err
  nfc:  ts | type | descriptor | hex(<=NB) | detail | err
Times ISO-8601 UTC. "…+N more bytes" marks truncated payloads. Secrets redacted.
App: <bundle> <version> | OS: iOS <ver> | Events: <n> over <range>

## timeline (ascending)
- 12:00:01.020Z ble connected device=Device-01
- 12:00:01.220Z ble serviceDiscovered uuid=C0DEC0DE-2000-… mtu=247
- 12:00:01.400Z net POST /v1/sessions 200 142ms
- 12:00:02.010Z ble notification uuid=…1003 hex=01 0a ff …+12 more bytes "alert: LOW_BATTERY"
- 12:00:02.500Z nfc scanFailed "tag lost"
...
```

**JSONL format**: a 1-line header object (`{"_schema": "...", "app": ..., "range": ...}`)
followed by one compact JSON object per event, ascending time.

---

## 3. UI States

| State | When | UI shows | Actions |
|-------|------|----------|---------|
| Copy AI context | Any tab / Timeline, ≥1 entry | Toolbar "Copy for AI" | Copies `exportForLLM()` to pasteboard + toast "Copied N events" |
| Share AI context | Long-press the action | Share sheet with `.md`/`.jsonl` | Save/Send |
| Scope respects filters | Active tab/kind filter applied | Export honors current `include` selection | — |
| Empty | No entries | Action disabled | — |

---

## 4. Constraints & Invariants

- [ ] **Deterministic**: same snapshot + same options ⇒ byte-identical output (testable; required so agents/caches behave).
- [ ] **Bounded**: output size is a function of `maxEntriesPerStream` × `maxPayloadBytes`, not unbounded capture size.
- [ ] **Self-describing**: with `includeSchemaPreamble`, output is interpretable by a model with zero prior WireTap knowledge.
- [ ] **Redacted**: never emits a secret; inherits TRACER-002's already-redacted entries and adds no raw path.
- [ ] **Lossy-by-design but honest**: every truncation/cap is explicitly marked (`…+N more bytes`, `(showing newest 200 of 5,000)`).
- [ ] Pure function, main-actor snapshot, no IO, no third-party deps.

---

## 5. Acceptance Criteria

> `Tests/WireTapTests/LLMExportSpec.swift`.

### AC-1: Deterministic output
**Given** a fixed snapshot and fixed options
**When** `exportForLLM` is called twice
**Then** the two strings are byte-identical
**Automated**: `LLMExportSpec.test_AC1_deterministic`

### AC-2: Payload truncation is marked
**Given** a BLE entry with a 1 KB payload and `maxPayloadBytes = 256`
**When** exported
**Then** at most 256 bytes of hex appear, followed by a `…+N more bytes` marker with the correct remaining count
**Automated**: `LLMExportSpec.test_AC2_payloadTruncationMarked`

### AC-3: Entry cap is marked
**Given** 500 network entries and `maxEntriesPerStream = 200`
**When** exported
**Then** exactly 200 (newest) appear and the output states `showing newest 200 of 500`
**Automated**: `LLMExportSpec.test_AC3_entryCapMarked`

### AC-4: Schema preamble present & toggleable
**Given** `includeSchemaPreamble = true` then `false`
**When** exported each way
**Then** the field-legend block is present in the first and absent in the second
**Automated**: `LLMExportSpec.test_AC4_schemaPreambleToggle`

### AC-5: Redaction holds
**Given** a redacted Authorization header
**When** exported in both `.markdown` and `.jsonl`
**Then** neither output contains the secret token
**Automated**: `LLMExportSpec.test_AC5_redactedInBothFormats`

### AC-6: Stream selection respected
**Given** `include = [.ble]`
**When** exported
**Then** only BLE events appear; no network/NFC lines
**Automated**: `LLMExportSpec.test_AC6_streamSelection`

### AC-7: JSONL is valid & parseable
**Given** `.jsonl` format
**When** exported
**Then** the header line and every event line independently parse as JSON; ascending time holds
**Automated**: `LLMExportSpec.test_AC7_jsonlEachLineParses`

### AC-8: Empty snapshot
**Given** no entries
**When** exported
**Then** a valid header/preamble is produced with an explicit "no events captured" note (no crash)
**Automated**: `LLMExportSpec.test_AC8_emptySnapshot`

---

## 6. Error Cases

| Error | Source | Behavior |
|-------|--------|----------|
| Non-UTF8 payload bytes | raw BLE/NFC data | Render as hex only (never force-unwrap a String) |
| Extremely large single field | misuse | Hard cap at `maxPayloadBytes`, marker appended |
| Pasteboard unavailable | platform | Fall back to share sheet; toast notes it |

---

## 7. Data Model Changes

| Model | Change | Reason |
|-------|--------|--------|
| `LLMExportOptions` (+ nested enums) | new public type | Controls |
| internal `LLMRenderer` | new file | Pure formatter; reused by TRACER-004 |
| — | no entry changes | Consumes TRACER-002 snapshot as-is |

---

## 8. Out of Scope

- Calling an LLM (that is TRACER-012). This spec only *produces text*.
- MCP transport (TRACER-004).
- Summarization/diagnosis logic — the agent does the reasoning; WireTap supplies clean context.
- Token *counting* (we bound by entries/bytes, a good proxy; exact tokenization is model-specific).

---

## 9. Open Questions

| # | Question | Resolution |
|---|----------|------------|
| 1 | Default format markdown or jsonl? | Markdown default (best for chat paste); jsonl for the MCP server. |
| 2 | Include decoded fields once TRACER-005 lands? | Yes — decoded fields are far more useful to an agent than hex; wire when available. |

---

## 10. Test Coverage Checklist

- [x] AC-1 deterministic
- [x] AC-2 payload truncation marked
- [x] AC-3 entry cap marked
- [x] AC-4 preamble toggle
- [x] AC-5 redaction (both formats)
- [x] AC-6 stream selection
- [x] AC-7 jsonl parseable
- [x] AC-8 empty snapshot

**Implemented in**: `Sources/WireTap/Core/LLMExport.swift` (`LLMExportOptions`, internal
`LLMRenderer` for markdown + jsonl, `WireTap.exportForLLM(...)`). Tests:
`Tests/WireTapTests/LLMExportSpec.swift`. The renderer is the shared formatter the
`wiretap-mcp` server's timeline tools reuse.
