# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- **`WireTapCore` SPM target** (TRACER-013) — release-safe module split. `WireTapCore` contains
  all models, serialization, redaction, decoders, and the LLM renderer. The `WireTap` Inspector
  target (views, overlay, `URLProtocol`) depends on it via `@_exported import WireTapCore`,
  so `import WireTap` is unchanged for all existing DEBUG consumers.
- **`WireTapReport`** — production-safe diagnostic report builder (BLE + NFC only). Accepts
  caller-supplied events, applies registered decoders and device-name anonymization
  (`WireTapPrivacyLevel.standard` by default), and emits a `.wiretapsession` JSON with
  `network: []`. No passive capture, no disk writes, no new permissions required.
- **`BleDecoderRegistry` protocol** — `BleStore` and `WireTapReport` both conform, so
  `registerAll(on:)` decoder helpers work on both the DEBUG and release paths without source
  changes to the caller.
- **`WireTapPrivacyLevel` enum** — `.standard` (last 4 chars of device name, `***` prefix)
  / `.verbose` (full names, DEBUG only).
- **`WireTapCoreTests` test target** — Core unit tests with no Inspector dependency.
  Includes `WireTapReportSpec` (12 tests) covering all TRACER-013 acceptance criteria, and
  `ExternalConsumerSpec` (plain `import WireTapCore`, no `@testable`) validating the public
  API surface exactly as an external release consumer sees it.
- **Public initializers + `current()` on `AppInfo` / `EnvInfo`** — previously internal-only,
  which would have blocked external consumers from constructing a `WireTapReport` at all.
  Caught by the external-consumer validation pass.
- **Cross-toolchain fixture** — `wiretap-mcp/test/fixtures/report.wiretapsession` is emitted
  by Swift `WireTapReport` (privacy `.standard`); a Node regression test locks the guarantee
  that every MCP tool parses a production field report (anonymized devices, `network: []`).

### Fixed
- `wiretap-mcp`: `summarizeBle` now renders decoder-produced named fields (`{k=v}`) in
  `wiretap_query_ble`, `wiretap_search`, and `wiretap_get_overview` output — previously the
  fields were present in the session JSON but invisible to the agent in those three tools.
- **Live MCP bridge** (`WireTap.startLocalBridge(port:)` / `stopLocalBridge()`) — a
  read-only HTTP/1.1 server bound to 127.0.0.1, serving the current capture so
  `wiretap-mcp` can query traffic as it happens without a file export step (TRACER-004
  AC-7/AC-8). `#if DEBUG` only.
- `wiretap-mcp` promoted to a **git submodule** (`wiretap-mcp/`) — `git clone
  --recurse-submodules` now fetches both the Swift package and the MCP server.
- **`wiretap-mcp` live mode** — `--live [port]`, `WIRETAP_BRIDGE_URL`, and
  `WIRETAP_BRIDGE_PORT` connect the MCP server to the running app's bridge.
- **MCP resources** — `wiretap://session/current` and `wiretap://session/{path}` let
  agents read session JSON directly as a resource without calling a tool.
- **Canned prompts** — `diagnose-disconnect` and `explain-network-failures` pre-fill
  the relevant capture context and a triage instruction for the agent.
- `LocalBridgeSpec` — 6 new Swift tests covering AC-7 (read-only) and AC-8
  (localhost-only), plus endpoint smoke tests.
- 3 additional Node tests covering `get_overview`, `get_nfc_records`, and `search`
  (previously untested tools).

## [1.0.0] - 2026-06-05

Initial public release.

### Added
- Network capture via `WireTapURLProtocol` (`URLProtocol`-based), with automatic `Authorization`
  redaction and cURL reconstruction.
- BLE event capture via the `BleEventObserver` protocol (19 event types) and `BleWireTapObserver`.
- NFC event capture via the `NfcEventObserver` protocol and `NfcWireTapObserver`.
- SwiftUI inspector UI (`WireTapView`) with Network / BLE / NFC tabs — filters, search,
  hex/ASCII payload view, cURL, and share.
- Chucker-style floating bubble (`WireTap.installFloatingButton()`), reachable from any screen.
- Unified cross-stream **Timeline** tab (TRACER-002).
- **Session persistence** across relaunch — opt-in `WireTap.configure(storage: .disk())` (TRACER-001).
- **Session export / import** as `.wiretapsession` bundles (TRACER-002).
- **LLM export** ("Copy for AI") — compact, redacted, token-bounded (TRACER-003).
- Companion `wiretap-mcp` Node server reading exported sessions (file mode) (TRACER-004).
- **Pluggable BLE decoders** — `WireTap.ble.registerDecoder(forCharacteristic:)` (TRACER-005).
- **Configurable redaction** for headers and JSON body keys via `WireTap.redaction` (TRACER-010).
- Connection lifecycle view and cross-radio correlation (TRACER-006, TRACER-007).

[Unreleased]: https://github.com/karkipsn/WireTap/compare/1.0.0...HEAD
[1.0.0]: https://github.com/karkipsn/WireTap/releases/tag/1.0.0
