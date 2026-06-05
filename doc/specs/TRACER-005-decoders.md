# Feature Spec: Pluggable Protocol Decoders

**Spec ID**: TRACER-005
**Component**: WireTap (core + export + UI) and `wiretap-mcp` (render parity)
**Author**: Poshan Karki
**Status**: Implemented
**Created**: 2026-06-04
**Last updated**: 2026-06-04
**Depends on**: TRACER-002 (export), TRACER-003 (LLM render)
**Unlocks**: the BLE/NFC hardware niche — the single highest-value feature for device teams

---

## 1. Summary

Raw BLE payloads render as hex/ASCII today, which is nearly useless to a human or an AI
agent staring at `01 0a ff 00 …`. Hardware teams already know what those bytes *mean* — their
app has a decoder (e.g. a GATT interpreter like `AppGattDecoder`). This spec exposes a **public extension point**
so a consumer registers a decoder closure per characteristic UUID, and WireTap renders the
payload as **named fields** everywhere: inspector UI, `.wiretapsession` export, and the LLM text
an agent reads.

This is what makes WireTap genuinely useful for connected-device debugging rather than "hex with
extra steps", and it's the differentiator no general inspector offers.

**Parity invariant:** decoded fields must render identically in the Swift LLM export and the
`wiretap-mcp` Node renderer (the golden test from TRACER-004 is extended to cover a decoded entry).

---

## 2. Public API Surface

```swift
public extension BleStore {
    /// Register a decoder for a characteristic UUID. When a logged BLE entry carries
    /// data for this UUID, its bytes are decoded into named fields. Case-insensitive.
    func registerDecoder(forCharacteristic uuid: String,
                         _ decode: @escaping @Sendable (Data) -> [String: String])

    /// Remove a previously registered decoder.
    func removeDecoder(forCharacteristic uuid: String)

    /// Remove all registered decoders.
    func clearDecoders()
}
```

| Symbol | Kind | Notes |
|--------|------|-------|
| `BleEntry.decoded` | new `public let [String: String]?` | Decoded fields, or nil. Codable; flows into persistence + export |
| `registerDecoder/removeDecoder/clearDecoders` | new funcs on `BleStore` | Registry keyed by lowercased UUID |
| `BleRecord.decoded` | new field on the export DTO | Carries decoded fields into `.wiretapsession` |

**Behavior:** at `BleStore.log(_:)`, if the entry has `data` and a `uuid` with a registered
decoder and `decoded == nil`, the decoder runs (on the main actor) and a non-empty result is
attached. An empty result leaves `decoded == nil` (no clutter). Decoders registered after an
entry was logged do not retroactively decode it.

---

## 3. UI / Render States

| Surface | Without decoder | With decoder |
|---------|-----------------|--------------|
| BLE detail view | hex + ASCII | hex + ASCII **plus a "Decoded" section** of key/value rows |
| `.wiretapsession` export | `hex` only | `hex` + `decoded: {…}` |
| LLM export line | `… hex=01 0a …` | `… hex=01 0a … {field=value …}` (sorted keys, after hex) |

---

## 4. Constraints & Invariants

- [ ] **Opt-in & additive** — no decoder registered ⇒ behavior is exactly as today (`decoded == nil`).
- [ ] **UUID match is case-insensitive** (BLE UUIDs vary in case across stacks).
- [ ] **Decoder runs at capture**, on the main actor; closures are `@Sendable` and return a plain dict.
- [ ] **Empty result is not clutter** — an empty dict leaves `decoded == nil`.
- [ ] **Redaction still applies** — decoders see already-captured bytes; a decoder must not be a
      back door for secrets (document: don't decode secret material into plaintext fields).
- [ ] **Render parity** — Swift and Node produce byte-identical decoded output (golden test).

---

## 5. Acceptance Criteria

> Swift: `Tests/WireTapTests/BleDecoderSpec.swift`. Node parity: extended golden in
> `wiretap-mcp/test/server.test.ts` (AC-2).

### AC-1: Registered decoder attaches named fields
**Given** a decoder registered for UUID `X`
**When** a BLE entry with data and uuid `X` is logged
**Then** `entry.decoded` equals the decoder's output
**Automated**: `BleDecoderSpec.test_AC1_decoderAttachesFields`

### AC-2: No decoder ⇒ no decoded
**Given** no decoder for the entry's UUID
**When** the entry is logged
**Then** `entry.decoded == nil`
**Automated**: `BleDecoderSpec.test_AC2_noDecoderLeavesNil`

### AC-3: UUID match is case-insensitive and scoped
**Given** a decoder registered for `"c0de...1003"`
**When** an entry with uuid `"C0DE...1003"` is logged, and another with a different uuid
**Then** the first is decoded; the second has `decoded == nil`
**Automated**: `BleDecoderSpec.test_AC3_caseInsensitiveAndScoped`

### AC-4: Empty decode result leaves nil
**Given** a decoder that returns `[:]`
**When** an entry is logged
**Then** `entry.decoded == nil`
**Automated**: `BleDecoderSpec.test_AC4_emptyResultIsNil`

### AC-5: Decoded survives session export round-trip
**Given** a decoded BLE entry
**When** the session is exported and re-imported
**Then** the `BleRecord.decoded` fields are intact
**Automated**: `BleDecoderSpec.test_AC5_decodedRoundTripsExport`

### AC-6: Decoded appears in LLM export
**Given** a decoded BLE entry
**When** `exportForLLM()` renders
**Then** the entry's line contains the decoded `key=value` fields
**Automated**: `BleDecoderSpec.test_AC6_decodedInLLMExport`

### AC-7: removeDecoder stops decoding
**Given** a decoder registered then removed
**When** a matching entry is logged
**Then** `entry.decoded == nil`
**Automated**: `BleDecoderSpec.test_AC7_removeDecoder`

### AC-8 (Node parity): golden includes a decoded entry
**Given** a Swift-emitted golden session containing a decoded BLE entry
**When** the Node `wiretap_get_timeline` renders it
**Then** the output is byte-identical to the Swift golden (decoded fields included)
**Automated**: `wiretap-mcp test/server.test.ts AC-2` (regenerated golden)

---

## 6. Error Cases

| Error | Behavior |
|-------|----------|
| Decoder throws (it can't — non-throwing closure) | n/a by type |
| Decoder returns huge dict | rendered as-is; payload byte cap (TRACER-003) still applies to `hex`, not decoded fields — document |
| Decoder registered for malformed UUID | stored as given (lowercased); simply never matches |

---

## 7. Data Model Changes

| Model | Change | Reason |
|-------|--------|--------|
| `BleEntry` | add `decoded: [String: String]?` (Codable) | carry decoded fields |
| `BleStore` | add decoder registry `[String: @Sendable (Data) -> [String:String]]` | the extension point |
| `BleRecord` (export DTO) | add `decoded` | export decoded fields |
| Node `BleEntry` type + `llm.ts` | add `decoded` passthrough + render | parity |

---

## 8. Out of Scope

- A library of built-in decoders (this is the *mechanism*; decoders are the consumer's domain).
- NFC decoders (same pattern could follow as TRACER-005b; not now).
- Decoding inside `wiretap-mcp` (it renders decoded fields the producer already attached; it
  does not decode bytes itself).

---

## 9. Open Questions

| # | Question | Resolution |
|---|----------|------------|
| 1 | Decode at capture vs. at render? | **Capture** — so decoded fields persist and export without holding the closures. |
| 2 | Should decoded fields be redaction-scanned? | Document the caveat; generalized redaction is TRACER-010. |

---

## 10. Test Coverage Checklist

- [x] AC-1 attaches fields
- [x] AC-2 no decoder ⇒ nil
- [x] AC-3 case-insensitive + scoped
- [x] AC-4 empty ⇒ nil
- [x] AC-5 export round-trip
- [x] AC-6 in LLM export
- [x] AC-7 removeDecoder
- [x] AC-8 Node render parity — golden regenerated with a decoded entry; `wiretap-mcp` AC-2 byte-matches

**Implemented in**: `BleEntry.decoded` + `withDecoded` (`Core/BleEntry.swift`), decoder registry +
decode-at-log in `BleStore` (`Core/WireTap.swift`), `BleRecord.decoded` (`Core/SessionExport.swift`),
decoded rendering in `Core/LLMExport.swift` and the Node `src/llm.ts` (parity), and a "Decoded"
section in `Views/BLE/BleDetailView.swift`. Tests: `Tests/WireTapTests/BleDecoderSpec.swift` (7) +
`wiretap-mcp/test/server.test.ts` AC-2 golden.
