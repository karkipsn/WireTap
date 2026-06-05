# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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
