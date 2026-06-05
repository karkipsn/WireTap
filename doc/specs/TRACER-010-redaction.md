# Feature Spec: Configurable Redaction Rules

**Spec ID**: TRACER-010
**Component**: WireTap (core) — applies to every sink
**Author**: Poshan Karki
**Status**: Implemented
**Created**: 2026-06-05
**Last updated**: 2026-06-05
**Depends on**: TRACER-001/002/003 (the sinks redaction must cover)

---

## 1. Summary

Today redaction is a single hard-coded rule: replace the `Authorization` request header.
That was fine until TRACER-003 started exporting **request/response bodies on failures** —
now a token echoed in a body (e.g. a refresh flow, a misbehaving error payload) would reach
the export, clipboard, and AI agent in the clear.

This spec generalizes redaction into a **configurable rule set** — header names *and* body
field keys — applied at the one choke point every sink already funnels through
(`WireTapRedaction.redacted`, called before disk persistence and before session/LLM export).
Sensible defaults ship; consumers can extend them.

---

## 2. Public API Surface

```swift
public struct WireTapRedactionConfig: Sendable {
    public var redactedHeaders: Set<String>   // header names, case-insensitive
    public var redactedBodyKeys: [String]      // JSON keys whose string value is masked
    public var placeholder: String             // default "[redacted]"
    public init(redactedHeaders: Set<String>, redactedBodyKeys: [String], placeholder: String = "[redacted]")
    public static let `default`: WireTapRedactionConfig
}

public extension WireTap {
    /// The active redaction rules. Set once at startup to extend the defaults.
    static var redaction: WireTapRedactionConfig { get set }   // @MainActor
}
```

**Defaults:**
- headers: `authorization, cookie, set-cookie, x-api-key, x-auth-token, proxy-authorization`
- body keys: `password, token, access_token, refresh_token, secret, api_key, apikey, authorization`
- placeholder: `[redacted]`

**Behavior:** `WireTapRedaction.redacted(_ entry, config:)` returns a copy with matching
request/response **headers** replaced by the placeholder, and matching **JSON string fields**
in request/response **bodies** masked (`"token":"abc"` → `"token":"[redacted]"`). Key match is
case-insensitive. Applied at capture-to-sink time, so nothing unredacted reaches disk, export,
or the MCP server (which reads the already-redacted export).

---

## 3. Constraints & Invariants

- [ ] **One choke point.** All sinks redact via `WireTapRedaction.redacted(_:config:)`; no sink
      serializes a raw entry.
- [ ] **Deterministic.** Redaction is pure string work (regex on body, dict on headers) — no
      JSON re-serialization that could reorder keys. Same input ⇒ same output (keeps the golden stable).
- [ ] **Additive & safe default.** With the default config, prior behavior (Authorization masked)
      still holds; bodies without sensitive keys are unchanged.
- [ ] **No new leak path.** Body redaction must run wherever bodies are exported (TRACER-003).
- [ ] **Render parity untouched.** Redaction changes *content*, not *format* — Swift/Node golden
      stays valid as long as fixtures contain no sensitive keys.

---

## 4. Acceptance Criteria

> `Tests/WireTapTests/RedactionSpec.swift`. `setUp` resets `WireTap.redaction = .default`.

### AC-1: Default redacts sensitive headers
**Given** default config and an entry with `Authorization` + `Cookie` headers
**When** redacted
**Then** both values are the placeholder; the secret strings are gone
**Automated**: `RedactionSpec.test_AC1_defaultHeaders`

### AC-2: Default redacts sensitive body fields (request + response)
**Given** a body `{"token":"abc","user":"bob"}` in both request and response
**When** redacted
**Then** `token` → `[redacted]`, `user` preserved, in both bodies
**Automated**: `RedactionSpec.test_AC2_bodyFields`

### AC-3: Custom rules extend the defaults
**Given** `WireTap.redaction` adds header `x-trace` and body key `pin`
**When** an entry with those is redacted
**Then** both are masked; an unlisted header/key is preserved
**Automated**: `RedactionSpec.test_AC3_customRules`

### AC-4: Redaction reaches the LLM export bodies
**Given** a FAILED network entry whose response body contains `"token":"leak"`
**When** `exportForLLM()` renders
**Then** the output contains `"token":"[redacted]"` and never `leak`
**Automated**: `RedactionSpec.test_AC4_llmExportRedactsBody`

### AC-5: Non-sensitive content is untouched
**Given** a body `{"error":"device not authenticated"}` (no sensitive keys)
**When** redacted
**Then** it is byte-for-byte unchanged (determinism / golden safety)
**Automated**: `RedactionSpec.test_AC5_nonSensitiveUnchanged`

### AC-6: Redaction precedes disk persistence
**Given** `.disk` storage and an entry with a body `"password":"hunter2"`
**When** persisted and the raw file is read back
**Then** the file contains `[redacted]` and never `hunter2`
**Automated**: `RedactionSpec.test_AC6_redactedBeforeDisk`

---

## 5. Out of Scope

- Redacting **binary BLE/NFC payloads** (no schema; decoders are the consumer's place to omit
  secrets — documented).
- Full JSON-path redaction / nested key targeting (regex on `"key":"value"` covers the common
  case; embedded-quote values are a known limitation).
- Encrypting data at rest (DEBUG tool).

---

## 6. Data Model Changes

| Model | Change |
|-------|--------|
| `WireTapRedactionConfig` | new public struct (`Core/Redaction.swift`) |
| `WireTapRedaction.redacted(_:config:)` | gains `config:`; adds header-set + body-key redaction |
| `WireTap.redaction` | new `@MainActor` static var, default `.default` |
| call sites | `NetworkStore.record`, `WireTap.makeSession` pass `WireTap.redaction` |

---

## 7. Test Coverage Checklist

- [x] AC-1 default headers
- [x] AC-2 body fields (req+resp)
- [x] AC-3 custom rules
- [x] AC-4 LLM export bodies
- [x] AC-5 non-sensitive unchanged
- [x] AC-6 before disk

**Implemented in**: `Core/Redaction.swift` (`WireTapRedactionConfig`, `WireTapRedaction.redacted(_:config:)`),
`WireTap.redaction` static var, call sites in `NetworkStore.record` + `WireTap.makeSession`. Tests:
`Tests/WireTapTests/RedactionSpec.swift` (6). Golden/Node parity unaffected (fixtures carry no
sensitive keys). Known limit: body matcher targets simple `"key":"value"` JSON strings.
