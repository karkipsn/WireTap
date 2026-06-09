# WireTap — Specs & Roadmap

> Spec index for the standalone WireTap package. Each feature has a `TRACER-NNN`
> ID, an owner, a status, and (for built features) a one-to-one mapping to
> automated tests in `Tests/WireTapTests/`.
>
> **Maintained by**: Poshan Karki
> **Last updated**: 2026-06-09

---

## North Star

> **WireTap is the in-app inspector that lets a developer — and their AI coding
> agent — *see* a connected-device app's BLE, NFC, and HTTP traffic in one place.**

Network-only inspectors are a saturated category (Pulse ~7k★, DebugSwift, Wormholy,
netfox). WireTap does **not** compete there on depth. Its defensible position is the
combination no mainstream package offers:

1. **BLE + NFC + Network** captured in one embeddable inspector, behind a clean
   observer-protocol architecture that compiles out of release builds.
2. **Runtime radio visibility for AI agents.** Every serious 2026 debug tool
   (Jam, Chrome DevTools MCP, Fiddler) feeds its captured data to coding agents
   over MCP — but all of them are network/web only. When a BLE/NFC app fails,
   the agent is blind. WireTap already captures that data; exposing it over MCP
   makes WireTap the only way an agent can reason about a connected-device app's
   radio behavior.

Everything in this roadmap serves one of those two pillars. We do **not** chase
network-inspector parity with Pulse where it does not reinforce the niche.

---

## Build sequence

The recommended order — each item is self-contained and reused by the next:

```
TRACER-001  Session Persistence ─┐
TRACER-002  Session Export/Import ┼─► foundation: durable, shareable sessions
TRACER-003  LLM-Optimized Export ─┘   (same serialization the MCP server reuses)
TRACER-004  wiretap-mcp Server  ──────► the headline differentiator
```

Then the niche-lock-in wave (TRACER-005…008) and DX wins (TRACER-009…012).

---

## Feature index

| ID | Feature | Tier | Priority | Status | Spec |
|----|---------|------|----------|--------|------|
| TRACER-001 | Session Persistence | Foundation | P0 | Implemented | [spec](TRACER-001-session-persistence.md) |
| TRACER-002 | Unified Session Export / Import | Foundation | P0 | Implemented | [spec](TRACER-002-session-export.md) |
| TRACER-003 | LLM-Optimized Export | AI layer | P0 | Implemented | [spec](TRACER-003-llm-export.md) |
| TRACER-004 | `wiretap-mcp` MCP Server | AI layer | P1 | Implemented | [spec](TRACER-004-mcp-server.md) |
| TRACER-005 | Pluggable Protocol Decoders | Niche | P1 | Implemented | [spec](TRACER-005-decoders.md) |
| TRACER-006 | Connection Lifecycle Timeline | Niche | P1 | Implemented | [spec](TRACER-006-lifecycle.md) |
| TRACER-007 | Cross-Radio Correlation | Niche | P2 | Implemented | [spec](TRACER-007-correlation.md) |
| TRACER-008 | Session Diff | Niche | P2 | Implemented | [spec](TRACER-008-diff.md) |
| TRACER-009 | Test-Oracle API | DX | P1 | Planned | _stub below_ |
| TRACER-010 | Configurable Redaction Rules | DX | P1 | Implemented | [spec](TRACER-010-redaction.md) |
| TRACER-011 | os_log / SwiftLog Bridge | DX | P2 | Planned | _stub below_ |
| TRACER-012 | In-App "Explain" (BYO key) | AI layer | P2 | Planned | _stub below_ |

Tiers: **Foundation** (close the parity gap), **AI layer** (the differentiator),
**Niche** (lock in the BLE/NFC hardware audience), **DX** (adoption & trust).

---

## Planned-feature stubs

Full specs are written just-in-time, before implementation. Until then:

### TRACER-005 — Pluggable Protocol Decoders
Let the consumer register a decoder closure per characteristic UUID
(`WireTap.ble.registerDecoder(for:uuid) { data -> [String: String] }`) so raw BLE
payloads render as named fields, not just hex/ASCII. The data layer already does
this internally (`AppGattDecoder`); this exposes it as a public extension
point. Highest-value single feature for hardware teams.

### TRACER-006 — Connection Lifecycle Timeline
A timeline/sequence view of the BLE connect → discover → pair → auth → notify
lifecycle for a single session, so the "why did reconnect fail" class of bug is
visible at a glance. Derived purely from existing `BleEntry` events; no new capture.

### TRACER-007 — Cross-Radio Correlation
Stitch an NFC tap → the BLE connection it triggered → the network session that
synced into one unified, time-ordered timeline. Correlation by timestamp + a
optional `correlationId` on entries. Unique to WireTap's multi-radio capture.

### TRACER-008 — Session Diff
Load two persisted/exported sessions and diff them ("working pairing vs failing
pairing"), highlighting divergent events. Builds on TRACER-001/002.

### TRACER-009 — Test-Oracle API
Expose stores so XCTest specs can assert on captured traffic
(`XCTAssertTrue(WireTap.ble.contains(.notification, uuid: ...))`), turning
WireTap into a test oracle. Plugs into spec-driven workflows.

### TRACER-010 — Configurable Redaction Rules
Generalize the hard-coded `Authorization` redaction into a rule set
(`WireTap.redaction.redactHeaders = [...]`, body key patterns, BLE UUID masks).
Must run *before* persistence/export so secrets never hit disk.

### TRACER-011 — os_log / SwiftLog Bridge
Optional ingestion of `os.Logger` / swift-log records into a fourth "Logs" tab so
general app logs share the timeline. Partial parity with Pulse's logging system.

### TRACER-012 — In-App "Explain" (bring-your-own-key)
Opt-in inline LLM diagnosis on a failing entry. No key is ever shipped; the
consumer provides an endpoint/key. Reuses TRACER-003 serialization for the prompt.

---

## Conventions

- **IDs are permanent.** Never reuse a `TRACER-NNN`.
- **One AC ⇄ one test.** Every `AC-N` names a test method in `Tests/WireTapTests/`.
- **Redaction is a hard invariant.** No spec may persist, export, or transmit an
  unredacted secret. Redaction runs at capture time, before any sink.
- **Release-build safety.** Nothing here may add cost to release builds beyond the
  existing `weak var` / injectable-config no-ops, unless the spec explicitly opts in.
- Status: `Draft → Review → Approved → Implemented`.
