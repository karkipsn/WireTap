# Feature Spec: `wiretap-mcp` MCP Server

**Spec ID**: TRACER-004
**Component**: `wiretap-mcp` (new companion executable) + optional in-app local bridge
**Author**: Poshan Karki
**Status**: Implemented (file mode) — live bridge pending
**Created**: 2026-06-04
**Last updated**: 2026-06-04
**Depends on**: TRACER-002 (`.wiretapsession` schema), TRACER-003 (`LLMRenderer`)
**Unlocks**: the product's headline differentiator

---

## 1. Summary

This is the feature that makes WireTap unique. In 2026 every serious debug tool feeds
its captured data to AI coding agents over **MCP** (Model Context Protocol) — Jam,
Chrome DevTools MCP, Fiddler — but **all of them are network/web only.** When a
developer vibe-codes a BLE/NFC app and pairing fails, the agent is blind to the radio
layer.

`wiretap-mcp` is a small MCP **server** that exposes a WireTap capture to any MCP client
(Claude Code, Cursor, VS Code, Windsurf). The developer asks *"why did the device
disconnect during auth?"* and the agent reads the **real BLE/NFC/network timeline** and
fixes the code against ground truth.

Two data sources, same tool surface:
- **File mode** (ship first): point the server at a `.wiretapsession` (TRACER-002) or a
  persisted store directory (TRACER-001). Zero app changes; works with any exported run.
- **Live mode** (phase 2): an opt-in in-app **local read-only HTTP bridge**
  (`WireTap.startLocalBridge(port:)`) that a simulator/device exposes on `localhost`, so
  the agent queries traffic *as it happens*.

---

## 2. Interface Surface

> MCP servers expose *tools*, *resources*, and *prompts*. This is the contract.

### Transport
- **stdio** (primary — how Claude Code / Cursor launch local servers).
- Streamable HTTP (optional, for remote/CI).

### Distribution
- A standalone executable target in **its own repo** (`wiretap-mcp`), referenced from a
  client config. Implementation language TBD (Open Question 1) — Swift (`swift-sdk` for
  MCP) keeps it one-ecosystem; Node maximizes `npx` reach. The **tool contract below is
  language-independent.**

### MCP Tools

| Tool | Args | Returns |
|------|------|---------|
| `wiretap_list_sessions` | `dir?` | sessions found (path, app, range, event counts) |
| `wiretap_get_overview` | `session?` | counts per stream, error count, time range, top error summaries |
| `wiretap_get_timeline` | `session?`, `kinds?`, `since?`, `until?`, `limit?` | LLM-rendered ascending timeline (reuses TRACER-003 `LLMRenderer`) |
| `wiretap_query_ble` | `type?`, `uuid?`, `device?`, `limit?` | matching BLE events |
| `wiretap_get_network_failures` | `session?`, `limit?` | non-2xx / errored requests with cURL + response excerpt |
| `wiretap_get_nfc_records` | `session?` | NFC events incl. decoded MIME/record descriptors |
| `wiretap_search` | `query`, `kinds?` | entries matching across uuid/url/detail/device |

### MCP Resources
- `wiretap://session/current` — the active/most-recent session as `.wiretapsession` JSON.
- `wiretap://session/{id}` — a specific discovered session.

### MCP Prompts (canned, optional)
- `diagnose-disconnect` — pre-fills the BLE lifecycle + a "find the disconnect cause" instruction.
- `explain-network-failures` — pre-fills failed requests + a triage instruction.

### Optional in-app live bridge (phase 2)
```swift
extension WireTap {
    /// DEBUG-only, localhost, read-only JSON over HTTP. Off by default.
    public static func startLocalBridge(port: UInt16 = 8787)
    public static func stopLocalBridge()
}
```
- Endpoints mirror the tools: `GET /overview`, `/timeline`, `/ble?...`, `/network/failures`, `/nfc`.
- **Localhost only**, **read-only**, **redacted**, **DEBUG-gated**. No write/replay surface.

---

## 3. Operating States

| State | When | Behavior |
|-------|------|----------|
| File mode, session found | server started with a dir/file | Tools answer from the decoded session |
| File mode, no session | empty/missing path | `wiretap_list_sessions` returns empty; other tools return a clear "no session" message (not an error crash) |
| Live mode, bridge up | app running with `startLocalBridge` | Tools proxy to `localhost:port`, fresh data per call |
| Live mode, bridge down | app not running | Server reports bridge unreachable + suggests file mode |
| Schema mismatch | session newer major than server | Tool returns a clear upgrade message |

---

## 4. Constraints & Invariants

- [ ] **Read-only.** No tool or endpoint can modify, replay, or inject traffic. This is an inspection surface, full stop.
- [ ] **Redaction is upstream and trusted** — the server serves already-redacted TRACER-002 data and adds no de-redaction path.
- [ ] **Bounded responses** — every tool honors a `limit` and reuses TRACER-003 truncation so it never floods the agent's context.
- [ ] **Live bridge is localhost-only, DEBUG-only, opt-in** — never reachable off-device, never in release by default.
- [ ] **Deterministic for a fixed session** — same session + args ⇒ same answer (cache-friendly).
- [ ] Tool schemas are documented in the repo README so agents self-discover correctly.

---

## 5. Acceptance Criteria

> Server logic ⇄ `wiretap-mcp` repo tests. App-side bridge ⇄
> `Tests/WireTapTests/LocalBridgeSpec.swift`. MCP handshake ACs are validated with the
> official **MCP Inspector** (manual/integration).

### AC-1: Lists sessions in a directory
**Given** a directory with two `.wiretapsession` files
**When** `wiretap_list_sessions` runs
**Then** both are returned with path, app name, event counts, and time range
**Automated**: `wiretap-mcp: test_AC1_listSessions`

### AC-2: Timeline reuses the LLM renderer
**Given** a known session
**When** `wiretap_get_timeline` runs with no filters
**Then** output equals `LLMRenderer` output for that session (shared formatter, not a fork)
**Automated**: `wiretap-mcp: test_AC2_timelineMatchesRenderer`

### AC-3: BLE query filters correctly
**Given** a session with mixed BLE event types
**When** `wiretap_query_ble(type: "disconnected")` runs
**Then** only `disconnected` events return, newest-first, ≤ `limit`
**Automated**: `wiretap-mcp: test_AC3_bleQueryFilter`

### AC-4: Network failures only
**Given** a session with 200s and a 500 and a transport error
**When** `wiretap_get_network_failures` runs
**Then** only the 500 and the errored request return, each with a cURL string
**Automated**: `wiretap-mcp: test_AC4_networkFailuresOnly`

### AC-5: No-session is graceful
**Given** an empty directory
**When** any tool runs
**Then** it returns a structured "no session found" result, not a thrown/crash
**Automated**: `wiretap-mcp: test_AC5_noSessionGraceful`

### AC-6: Responses are bounded
**Given** a session with 10,000 events and `limit: 50`
**When** `wiretap_get_timeline` runs
**Then** ≤ 50 events return with an explicit truncation note
**Automated**: `wiretap-mcp: test_AC6_responsesBounded`

### AC-7: Read-only guarantee
**Given** the full tool/endpoint surface
**When** enumerated
**Then** none accept a mutating verb/arg; the live bridge serves only `GET` and rejects others with 405
**Automated**: `LocalBridgeSpec.test_AC7_bridgeIsReadOnly`

### AC-8: Live bridge is localhost & DEBUG-gated
**Given** `startLocalBridge()`
**When** the listening socket is inspected
**Then** it binds `127.0.0.1` only (not `0.0.0.0`); the symbol is unavailable / no-ops in a release configuration
**Automated**: `LocalBridgeSpec.test_AC8_localhostOnly`

### AC-9: MCP handshake (integration)
**Given** the server launched over stdio
**When** connected via MCP Inspector
**Then** `initialize` succeeds and all tools/resources/prompts are listed with valid schemas
**Automated**: manual — documented MCP Inspector checklist in the `wiretap-mcp` README

---

## 6. Error Cases

| Error | Source | Behavior |
|-------|--------|----------|
| Malformed session file | bad JSON | Tool returns a clear parse-error result, server stays up |
| Unsupported schema major | newer file | Upgrade message naming the version |
| Live bridge unreachable | app not running | "bridge unreachable, falling back / use file mode" |
| Port already in use | bridge start | Throw with the conflicting port; suggest another |
| Client requests unknown tool | MCP client | Standard MCP method-not-found error |

---

## 7. Data Model Changes

| Model | Change | Reason |
|-------|--------|--------|
| — (app) | reuse TRACER-002 `WireTapSession` + TRACER-003 `LLMRenderer` | Single source of truth for shape & formatting |
| `wiretap-mcp` repo | new project | MCP server impl + tool schemas |
| `LocalBridge` (internal, app) | new file, DEBUG-only | localhost read-only HTTP over `Network`/`NWListener` |

---

## 8. Out of Scope

- Traffic **modification / replay / mocking** (Fiddler-style) — read-only is a hard line.
- Authentication on the live bridge beyond localhost binding (DEBUG tool; document the caveat).
- Hosted/cloud session storage or a remote viewer (cf. Pulse Pro — not a goal).
- The agent's reasoning quality — WireTap supplies ground-truth context; the model reasons.

---

## 9. Open Questions

| # | Question | Resolution |
|---|----------|------------|
| 1 | Server language: Swift MCP SDK vs Node? | Lean **Swift** (one ecosystem, shares types with the package); reconsider Node if `npx` distribution proves decisive for non-Swift teams. |
| 2 | Ship file mode and live mode together or stage? | **Stage**: file mode first (zero app changes, immediate value), live bridge as phase 2. |
| 3 | How does live mode find the active session across simulator/device? | Bridge advertises a fixed localhost port; document `xcrun simctl` port-forward for device. Track separately. |

---

## 10. Test Coverage Checklist

- [x] AC-1 list sessions
- [x] AC-2 timeline reuses renderer — **byte-identical golden test** vs Swift TRACER-003 output
- [x] AC-3 BLE query filter
- [x] AC-4 network failures only
- [x] AC-5 no-session graceful
- [x] AC-6 responses bounded
- [x] AC-7 read-only guarantee — by name + every tool annotated `readOnlyHint: true`
- [ ] AC-8 localhost & DEBUG-gated bridge — **deferred** (live mode not built)
- [x] AC-9 MCP handshake — verified manually over stdio (initialize + tools/list + tools/call)

**Implemented in**: `LocalPackages/wiretap-mcp/` — `src/llm.ts` (port of the Swift TRACER-003
renderer), `src/tools.ts` (the 7 read-only tools), `src/index.ts` (thin MCP registration via
`registerTool`). Tests: `test/server.test.ts` (`npm test`), with golden fixtures emitted by
Swift in `test/fixtures/`. **Not built:** the live localhost bridge (AC-8), MCP resources, and
canned prompts — all remain in the roadmap.
