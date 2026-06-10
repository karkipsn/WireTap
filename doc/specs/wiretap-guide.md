# WireTap in MS2 — Usage Guide

> How the MS2 iOS app uses the **WireTap** debug inspector, what's now wired in, and
> how to hand a captured BLE/NFC/network session to an AI coding agent.
>
> **Audience**: MS2 iOS developers. **Last updated**: 2026-06-10.
> Package + roadmap live in [`LocalPackages/WireTap/doc/specs/`](../LocalPackages/WireTap/doc/specs/).

---

## 1. What it is

WireTap is a drop-in, in-app inspector (a local Swift package, `LocalPackages/WireTap`)
that captures the app's **HTTP, BLE, and NFC** traffic and shows it in a floating
overlay. The **inspector is DEBUG-only** — every capture/UI call site is compiled out of
release builds.

> **Release builds that ship MS2-FEAT-004** (Connection Troubleshooter) link `WireTapCore`
> (~185 KB: serialization and redaction only — **no capture engine, no UI**). The DEBUG
> bridge (`startLocalBridge`) and all inspector code contribute zero bytes to release.
> Device names in field reports are anonymized by default; network/HTTP data **cannot**
> appear in them. See [§7 Release diagnostics](#7-release-diagnostics-ms2-feat-004) and
> the TRACER-013 spec for the App Store / data-law analysis.

It's wired into MS2 in three places, all `#if DEBUG`:

| Where                                       | What it does                                                                                            | File                                                                   |
| ------------------------------------------- | ------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------- |
| `AppContainer.init`                         | Attaches BLE/NFC observers, the network `URLProtocol`, enables disk persistence, registers MS2 decoders | [`App/AppContainer.swift`](../Sources/MS2App/App/AppContainer.swift)   |
| `DebugBubbleInstaller`                      | Installs the floating bubble (Timeline + Network + BLE + NFC tabs)                                      | [`Debug/DebugBubble.swift`](../Sources/MS2App/Debug/DebugBubble.swift) |
| `BleWireTapObserver` / `NfcWireTapObserver` | Bridge SDK events → WireTap entries                                                                     | [`Debug/`](../Sources/MS2App/Debug/)                                   |

The SDK layer (`Ms2BleManager`, `NfcManager`, `Ms2ApiClient`) stays **WireTap-unaware** —
it just exposes observer hooks and an injectable `URLSession` config.

---

## 2. What's enabled now

Recent work turned on four capabilities. All are live in DEBUG builds:

1. **Unified Timeline tab.** The floating bubble opens with a **Timeline** that merges
   NFC → BLE → network events in time order — e.g. `NFC tap → connect → pair → authFailed
   → HTTP 401` on one screen. (`tabs: .all`.)
2. **Session persistence** (`WireTap.configure(storage: .disk())`). Captured traffic
   survives app relaunch / crash, so you can inspect the run that just failed.
3. **MS2 protocol decoders** ([`Debug/Ms2WireTapDecoders.swift`](../Sources/MS2App/Debug/Ms2WireTapDecoders.swift)).
   Reusing the production `Ms2GattInterpreter`, raw BLE payloads render as **named
   fields** instead of hex:
   - telemetry → `rmsTotal=2.130 rmsX=… rmsY=… rmsZ=…`
   - exposure → `dailyA8=1.500 points=… sessionDurationS=…`
   - alert → `alert=alert_low_battery alertType=30`
   - battery → `battery=87%`
4. **Export for humans and agents.** Each inspector's toolbar menu (`•••`) has:
   - **Copy for AI** — the whole capture as compact, redacted, LLM-ready text → clipboard.
   - **Export Session…** — a `.wiretapsession` JSON bundle → iOS share sheet.

Secrets are redacted before anything is persisted, exported, or copied — sensitive headers
(`Authorization`, `Cookie`, …) **and** JSON body keys (`token`, `password`, `secret`, …), via
the configurable `WireTap.redaction` rules (TRACER-010). Extend them in `AppContainer` if MS2's
API uses other field names. Note: binary BLE/NFC payloads aren't scanned — don't decode secret
material into named fields.

---

## 3. Day-to-day use

1. Run a **DEBUG** build on a device/simulator (not `-ms2_demo_mode` — the bubble is
   suppressed there to keep screenshots clean).
2. A small floating bubble appears. **Drag** to reposition, **tap** to open.
3. Use the app — pair, measure, sync. Watch the **Timeline** populate.
4. To investigate, tap an entry for full detail (BLE shows hex + ASCII + the **Decoded**
   field section; Network shows request/response + cURL).

---

## 4. Hand a session to an AI agent

This is the payoff: an agent can read MS2's actual radio behavior and reason about a
failure (e.g. the stale-bond reconnect / ECDSA auth issues) instead of guessing from code.

### Quick path — Copy for AI (no setup)

1. Reproduce the bug.
2. Bubble → `•••` → **Copy for AI**.
3. Paste into Claude Code / Cursor / any chat and ask: *"This is my app's BLE/NFC/network
   trace — why did pairing fail?"*

That's it. The clipboard text is self-describing (it includes a schema legend), so the
model needs no prior context.

### Tooled path — wiretap-mcp (agent queries the session)

For larger sessions or repeated questions, use the companion MCP server so the agent can
*query* the session with tools instead of reading one big paste.

1. Bubble → `•••` → **Export Session…** → save/share the `.wiretapsession` file to your Mac
   (Save to Files, AirDrop, or the simulator share sheet).
2. One-time: build the server.
   ```bash
   cd LocalPackages/wiretap-mcp && npm install && npm run build
   ```
3. Point your agent at it (Claude Code shown; Cursor uses `.cursor/mcp.json`):
   ```bash
   claude mcp add wiretap -- node "$PWD/dist/index.js" /path/to/your.wiretapsession
   ```
4. Ask: *"Use the wiretap tools — get the overview, then explain the disconnect."* The agent
   calls `wiretap_get_overview`, `wiretap_get_timeline`, `wiretap_query_ble`, etc.

See [`LocalPackages/wiretap-mcp/README.md`](../LocalPackages/wiretap-mcp/README.md) for the
full tool list and config.

> The MCP server reads the **`.wiretapsession`** export (the contract format). The on-disk
> *persistence* files (`network.jsonl` etc. in the app's Application Support) are an
> internal format for relaunch reload — use **Export Session…** to produce a file for the agent.

---

## 5. Add a decoder for another characteristic

Decoders are what make BLE payloads readable. To add one, extend
[`Ms2WireTapDecoders.swift`](../Sources/MS2App/Debug/Ms2WireTapDecoders.swift):

```swift
// 1. add the characteristic to the list
private static let characteristics: [CBUUID] = [
    Ms2Uuids.rmsTelemetryChar,
    // … add e.g. Ms2Uuids.logChar
]

// 2. map its parsed value to fields in `fields(forUUIDString:data:)`
case let .log(entry):
    return ["level": entry.level, "module": entry.module, "msg": entry.message]
```

The decoded fields then appear automatically in the inspector, the `.wiretapsession`
export, and the LLM text. The same `[String:String]` output is rendered identically by
the Swift package and the Node `wiretap-mcp` server (a golden test enforces this).

---

## 6. Production safety & limits (be aware)

- **Release builds:** the inspector is behind `#if DEBUG`. The observer hooks are
  `weak var` (nil in release); the `URLProtocol`, persistence, bubble, and views are never
  compiled in. If MS2-FEAT-004 ships, release links **`WireTapCore` only** — the
  serialization slice for diagnostic reports (§7). It performs no capture and has no UI.
- **Network scope:** WireTap sees traffic through the `URLSession` built from
  `WireTapURLProtocol.makeSessionConfiguration()` (wired in `AppContainer`). MS2 is native,
  so its API calls are captured; anything bypassing that session is not.
- **UI verified by build, not yet on-device:** the Timeline tab and export menu compile
  and the MS2 app builds, but a manual on-device walkthrough is still worth doing.
- **MCP live mode is built** (TRACER-004 phase 2): call `WireTap.startLocalBridge()` in
  DEBUG startup and launch the server with `--live` — the agent then queries the *running*
  app instead of a file export. Localhost-only, read-only, DEBUG-only.

---

## 7. Release diagnostics (MS2-FEAT-004)

The Connection Troubleshooter lets a **field worker on a release build** share a
diagnostics report that the whole WireTap toolchain (wiretap-mcp, "Copy for AI") reads
like any debug capture. This is the only WireTap surface that exists in production.

```swift
import WireTapCore   // release-safe — no inspector code

let report = WireTapReport(app: .current(), privacy: .standard)
Ms2WireTapDecoders.registerAll(on: report)   // same helper as the DEBUG path
connectionManager.bleHistory.forEach { report.add(ble: $0.asWireTapEntry()) }
nfcManager.tapHistory.forEach       { report.add(nfc: $0.asWireTapEntry()) }
let data = try report.exportData()           // .wiretapsession → share sheet
```

What MS2 must know:

- **BLE + NFC only.** `WireTapReport` has no way to include HTTP data — `network` is
  always `[]` in the export. URLs/headers/bodies can't leak into a field report.
- **Anonymization is on by default** (`privacy: .standard`): device names truncate to
  `***XXXX`. Never pass `.verbose` outside `#if DEBUG`.
- **One caveat:** BLE `detail`/`error` strings are **not** secret-scanned (same as debug).
  Review the `asWireTapEntry()` mapping — don't put tokens or user data into error text.
- **MS2 owns the consent UX**: inform the user what the report contains before the share
  sheet, and declare the data types in App Store Connect privacy labels. WireTap enforces
  the technical guarantees (no capture, no persistence, no auto-transmission); the policy
  obligations are the app's.

---

## 8. Reference

| Topic                                     | Doc                                                               |
| ----------------------------------------- | ----------------------------------------------------------------- |
| Package API, tabs, observers, entry types | [`WireTap/README.md`](../LocalPackages/WireTap/README.md)         |
| Feature specs & roadmap (TRACER-001…)     | [`WireTap/doc/specs/`](../LocalPackages/WireTap/doc/specs/)       |
| MCP server tools & agent setup            | [`wiretap-mcp/README.md`](../LocalPackages/wiretap-mcp/README.md) |
