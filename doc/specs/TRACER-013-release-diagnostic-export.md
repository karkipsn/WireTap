# Feature Spec: Release-Safe Diagnostic Export (`WireTapCore`)

**Spec ID**: TRACER-013
**Component**: WireTap Swift package — new `WireTapCore` SPM target + `WireTapReport` API
**Author**: Poshan Karki
**Status**: Implemented
**Created**: 2026-06-10
**Last updated**: 2026-06-10
**Depends on**: TRACER-002 (`.wiretapsession` schema), TRACER-005 (decoder registry),
TRACER-010 (redaction engine)
**Unlocks**: MS2-FEAT-004 (Connection Troubleshooter & Diagnostics Report)

---

## 1. Summary

WireTap today is **DEBUG-only**. Every capture call site compiles out of release builds — the
production binary ships zero WireTap code. This works perfectly for the inspector use case.

MS2 needs a **production** diagnostic report that a field worker can share from a release build
when a device fails to connect. That report must be **format-compatible** with a WireTap debug
session so the same `wiretap-mcp` tooling and "Copy for AI" flow can analyze it.

This spec does two things:

1. **Split** the package into a release-safe `WireTapCore` target (models, serialization,
   redaction, decoders) and the existing `WireTap` Inspector (capture engine, views, overlay —
   DEBUG-only as today).

2. **Add `WireTapReport`** — a minimal, privacy-first builder that a release app feeds with
   **BLE and NFC events only**, applies anonymization and decoding, and emits a valid
   `.wiretapsession` JSON + optional LLM text. **Network/HTTP capture is excluded from the
   production path by design** — it cannot be added without moving to DEBUG.

The result: a diagnostic log that is small, contains no HTTP request data, anonymizes device
identifiers by default, never captures passively, and requires no new permissions or privacy
manifest entries beyond what the app already declares.

---

## 2. Privacy-first design principles

These are invariants, not configuration options. Every decision below flows from them.

| Principle | What it means in practice |
|-----------|--------------------------|
| **Explicit-only** | `WireTapReport` is a serializer. It accepts events the app explicitly feeds it. It never installs observers, hooks, or intercepts. |
| **BLE + NFC only in production** | No `NetworkEntry` input on `WireTapReport`. HTTP request/response data (URLs, headers, bodies) never appears in a release diagnostic. |
| **Anonymize by default** | Device names and identifiers are truncated to their last 4 characters unless the caller explicitly opts into verbose mode. Opt-in is DEBUG-only via a compiler guard. |
| **Ephemeral** | `WireTapReport` holds its data in memory only. It does not write to disk, does not persist across launches, and has no background footprint. |
| **User-initiated share** | The report only leaves the device when the app explicitly presents a share sheet. No automatic upload, no background transmission. |
| **Redaction on by default** | The redaction config used in the release path defaults to `.default` (Authorization header masked, common secret keys masked). Opting out requires explicit config — not the happy path. |

---

## 3. What the production report contains (and does not contain)

### Included
- **BLE events**: event type (`connected`, `disconnected`, `authFailed`, etc.), anonymized device
  identifier (last 4 chars), characteristic UUID, event timestamp (ISO-8601), decoded named fields
  if a decoder is registered.
- **NFC events**: event type (`scanCompleted`, `recordParsed`, etc.), record descriptor/MIME type,
  event timestamp.
- **Session metadata**: app name + version, OS + OS version, session time range.

### Excluded — by design, not by oversight
- HTTP request/response data (URLs, headers, request/response bodies). These belong to the DEBUG
  inspector only. The `WireTapReport` API has no method to add a `NetworkEntry`.
- Full BLE device names. Truncated to last 4 characters (`***A1B2`) by default.
- Raw binary payloads beyond what a registered decoder explicitly surfaces as named fields.
- Any persistent identifier that could be used to track users across sessions.

---

## 4. Module split

### 4.1 Current state
One monolithic SPM target (`WireTap`) containing `Core/`, `Views/`, `Interceptors/`, `Overlay/`.
The split along the `Core/` directory boundary is already clean — zero reverse dependencies from
Core to Views, confirmed by audit (June 2026 commit `016959a`).

### 4.2 Package.swift after split

```swift
products: [
    .library(name: "WireTap",     targets: ["WireTap"]),      // unchanged — DEBUG inspector
    .library(name: "WireTapCore", targets: ["WireTapCore"]),  // new — release-safe
],
targets: [
    .target(
        name: "WireTapCore",
        path: "Sources/WireTapCore"          // Core/ files move here
    ),
    .target(
        name: "WireTap",
        dependencies: ["WireTapCore"],
        path: "Sources/WireTapInspector"     // Views/ + Overlay/ + Interceptors/ move here
    ),
    .testTarget(
        name: "WireTapCoreTests",
        dependencies: ["WireTapCore"],
        path: "Tests/WireTapCoreTests"       // Core unit tests — no Inspector dependency
    ),
    .testTarget(
        name: "WireTapTests",
        dependencies: ["WireTap"],
        path: "Tests/WireTapTests"           // existing Inspector tests, unchanged
    ),
]
```

### 4.3 Directory layout

```
Sources/
  WireTapCore/                    ← release-safe target
    WireTap.swift                 facade + stores (NetworkStore, BleStore, NfcStore)
    Redaction.swift               TRACER-010 — runs at capture, before any sink
    Persistence.swift             JSONL disk writer (opt-in)
    LocalBridge.swift             #if DEBUG — contributes 0 bytes in release (verified by nm)
    Models/
      BleEntry.swift  NfcEntry.swift  NetworkEntry.swift
    Export/
      SessionExport.swift         .wiretapsession types + makeSession/export/import
      LLMExport.swift             "Copy for AI" renderer
    Analysis/
      ConnectionLifecycle.swift  Correlation.swift  SessionDiff.swift
    Report/                       ← TRACER-013 (this spec)
      WireTapReport.swift  BleDecoderRegistry.swift  WireTapPrivacyLevel.swift

  WireTapInspector/               ← builds the `WireTap` product (DEBUG inspector)
    WireTap+Umbrella.swift        @_exported import WireTapCore
    Interceptors/WireTapURLProtocol.swift   (HTTP capture — stays DEBUG via Inspector)
    Overlay/WireTapOverlay.swift
    Views/  (all 11 view files — unchanged)

Tests/
  WireTapCoreTests/               ← no SwiftUI/UIKit dependency (AC-1 by construction)
    (all Core unit tests)
    WireTapReportSpec.swift       TRACER-013 acceptance criteria
    ExternalConsumerSpec.swift    plain `import WireTapCore` — public-API-only validation
  WireTapTests/                   ← Inspector smoke tests
```

### 4.4 Umbrella re-export

`Sources/WireTapInspector/WireTap+Umbrella.swift`:
```swift
@_exported import WireTapCore
// All WireTapCore symbols remain visible via `import WireTap`.
// Existing DEBUG consumers need zero source changes.
```

### 4.5 `WireTapURLProtocol` placement

`WireTapURLProtocol` (the HTTP interceptor) stays in `WireTapInspector`, not Core. It is a
capture component: it intercepts network traffic and writes into the live `NetworkStore`. Putting
it in Core would violate the "Core serializes what it's given" invariant and would enable passive
HTTP capture in release builds. That is explicitly not allowed.

---

## 5. New API: `WireTapReport`

### 5.1 `BleDecoderRegistry` protocol

The decoder registration pattern in MS2 today is:
```swift
Ms2WireTapDecoders.registerAll(on: WireTap.ble)   // BleStore, DEBUG
```
The `registerAll(on:)` helper needs to work on both `BleStore` (DEBUG) and `WireTapReport`
(release) without a source change to the decoder package. A protocol makes this seamless:

```swift
/// Anything that can accept BLE characteristic decoders.
/// Conformed to by BleStore (DEBUG inspector) and WireTapReport (release builder).
public protocol BleDecoderRegistry: AnyObject {
    func registerDecoder(
        forCharacteristic uuid: String,
        _ decode: @escaping @Sendable (Data) -> [String: String]
    )
}

// BleStore already has this exact signature — retroactive conformance, no source change:
extension BleStore: BleDecoderRegistry {}
```

### 5.2 Privacy level

```swift
/// Controls how BLE device identifiers appear in the exported report.
public enum WireTapPrivacyLevel: Sendable {
    /// Default. Device names are anonymized to "***XXXX" (last 4 chars only).
    /// Required for production / App Store release exports.
    case standard

    /// Full device names included. Must be guarded #if DEBUG at the call site.
    /// Never use in a path reachable from a release build.
    case verbose
}
```

### 5.3 `WireTapReport`

```swift
/// Release-safe diagnostic report builder. Accepts BLE and NFC events explicitly
/// supplied by the caller, applies anonymization and registered decoders, and emits
/// a .wiretapsession JSON compatible with the WireTap toolchain.
///
/// - No passive capture. No observers installed. No network data accepted.
/// - All data lives in memory only — no disk writes.
/// - Device identifiers are anonymized by default (WireTapPrivacyLevel.standard).
///
/// Usage:
///   let report = WireTapReport(app: AppInfo(...))
///   Ms2WireTapDecoders.registerAll(on: report)     // same as DEBUG path
///   connectionEvents.forEach { report.add(ble: $0.asWireTapEntry()) }
///   nfcEvents.forEach       { report.add(nfc: $0.asWireTapEntry()) }
///   let data = try report.exportData()             // .wiretapsession JSON
@MainActor
public final class WireTapReport: BleDecoderRegistry {

    // MARK: - Init

    public init(
        app: AppInfo,
        environment: EnvInfo? = nil,
        privacy: WireTapPrivacyLevel = .standard
    )

    // MARK: - Decoder registration (BleDecoderRegistry)

    public func registerDecoder(
        forCharacteristic uuid: String,
        _ decode: @escaping @Sendable (Data) -> [String: String]
    )

    // MARK: - Event ingestion
    // Network is intentionally absent. There is no addNetwork() method.

    public func add(ble entry: BleEntry)
    public func add(nfc entry: NfcEntry)

    // MARK: - Build

    /// Applies decoders to BLE payloads, anonymizes device identifiers per
    /// privacy level, and returns an immutable WireTapSession with network=[].
    /// Non-destructive — safe to call multiple times.
    public func build() -> WireTapSession

    // MARK: - Export

    /// Encodes the session as .wiretapsession JSON.
    /// `network` array in the output is always [].
    public func exportData() throws -> Data

    /// Optional: renders as LLM-optimized text (TRACER-003 format).
    /// Useful for attaching to a support ticket or AI-assisted triage.
    public func exportForLLM(_ options: LLMExportOptions = .init()) -> String
}
```

### 5.4 Anonymization behaviour

When `privacy == .standard` (the default and the only production-safe option):

```
Input device name / identifier:  "MS2-A1B2"   → output: "***A1B2"
Input device name:                "John's Headset" → output: "***eset"
Empty / nil:                      kept as-is
UUIDs (e.g. characteristic):      kept in full — UUIDs identify protocols, not people
```

BLE characteristic UUIDs are kept in full because they identify the protocol, not the person.
Device name/address strings are truncated because they can contain user-assigned names.

### 5.5 Typical consumer integration

```swift
// In the Connection Troubleshooter feature (release build)
import WireTapCore

func buildDiagnosticReport() throws -> Data {
    let report = WireTapReport(
        app: AppInfo(
            name: Bundle.main.displayName,
            bundleId: Bundle.main.bundleIdentifier ?? "",
            version: Bundle.main.shortVersionString
        ),
        environment: EnvInfo.current(),
        privacy: .standard          // default; be explicit for clarity
    )

    // Decoder registration — identical call to the DEBUG path, via BleDecoderRegistry protocol
    Ms2WireTapDecoders.registerAll(on: report)

    // Feed events from the app's own connection manager
    for event in connectionManager.bleConnectionLog {
        report.add(ble: event.asWireTapBleEntry())
    }
    for tap in nfcManager.recentTaps {
        report.add(nfc: tap.asWireTapNfcEntry())
    }

    return try report.exportData()  // .wiretapsession JSON, network=[]
}

// Share sheet — user-initiated only
let activityVC = UIActivityViewController(
    activityItems: [reportData],
    applicationActivities: nil
)
```

---

## 6. App Store and data law compliance

### 6.1 App Store guidelines

| Concern | How this spec addresses it |
|---------|---------------------------|
| Collecting data without consent (§5.1.1) | `WireTapReport` is explicit and user-initiated. The app controls when the report is built and when it is shared. No automatic collection. |
| Background data collection | `WireTapReport` has no background component. It holds data in memory during a single foreground call chain and releases it when the object is deallocated. |
| Required privacy manifest entries | `WireTapCore` does not call any Required Reason APIs (no `UserDefaults`, no `NSFileManager` path lookups, no tracking APIs). No `PrivacyInfo.xcprivacy` additions needed beyond what the app already declares for BLE/NFC. |
| Privacy nutrition label | The app using `WireTapReport` must declare **"Device ID"** if it includes BLE device addresses in the report. With `privacy: .standard` (truncation), this is a documentation concern for the app, not WireTap. WireTap itself is a library and declares no data collection. |

### 6.2 GDPR / CCPA

| Concern | How this spec addresses it |
|---------|---------------------------|
| Personal data in BLE events | Device names *can* be personal data (e.g., "John's iPhone"). `.standard` truncation reduces identifiability but does not eliminate it if the last 4 chars are unique in context. The app's privacy policy must describe what the report contains. This is the app's obligation, not WireTap's. |
| Data minimization (GDPR Art. 5(1)(c)) | Network data excluded. BLE names truncated. No persistent storage. Only the minimum needed to diagnose a connection failure. |
| Right to erasure | No persistent storage in `WireTapReport` — the in-memory object is released after use. The app is responsible for any storage of the emitted `Data`. |
| Consent and transparency | The app must obtain user consent before sharing a diagnostic report. The share sheet is user-initiated, but the app must inform the user what the report contains. Recommended: an "info" tap in the share flow that describes the report contents. This is the app's responsibility. |
| Data transfer outside EEA | The report only leaves the device when the user taps share. Where it goes is the app's and the receiver's responsibility. |

### 6.3 What WireTap guarantees vs. what the app is responsible for

**WireTap guarantees (enforced in code):**
- No network HTTP data in `WireTapReport`.
- Device names truncated to last 4 chars when `privacy: .standard`.
- No disk writes, no persistent storage, no background operation.
- No automatic transmission of any kind.

**The consuming app is responsible for:**
- Informing users what the diagnostic report contains before sharing.
- Obtaining consent where required by applicable law.
- Declaring relevant data types in App Store Connect privacy labels.
- Updating its privacy policy to mention BLE connection diagnostics if the feature ships.
- Handling the emitted `Data` object appropriately (not logging it, not caching it to disk unencrypted).

---

## 7. Consumer contract — what survives unchanged

All existing DEBUG call sites work without modification:

| Symbol | After split | Change? |
|--------|-------------|---------|
| `import WireTap` | `WireTap` product re-exports `WireTapCore` via `@_exported` | None |
| `WireTap.configure(storage: .disk())` | WireTapCore | None |
| `WireTap.ble` / `WireTap.nfc` | WireTapCore | None |
| `WireTapURLProtocol.makeSessionConfiguration(...)` | WireTapInspector | None |
| `WireTap.installFloatingButton(tabs: .all)` | WireTapInspector | None |
| `<Decoders>.registerAll(on: WireTap.ble)` | WireTapCore (BleStore now: BleDecoderRegistry) | None |
| `.wiretapsession` export / LLM export | WireTapCore | None |

New release-path additions:

| Symbol | Target | Notes |
|--------|--------|-------|
| `import WireTapCore` | WireTapCore product | New SPM product |
| `BleDecoderRegistry` | WireTapCore | New protocol |
| `WireTapPrivacyLevel` | WireTapCore | New enum |
| `WireTapReport` | WireTapCore | New type |

**SemVer**: additive — bump to `1.1.0`. MS2 pins `from: 1.0.0`, no update needed.

---

## 8. Acceptance criteria

### AC-1: Core target is capture-free
A test target depending **only** on `WireTapCore` builds and links. `WireTapURLProtocol`,
`WireTapOverlay`, and all SwiftUI symbols are absent from its link graph.
**Automated**: `WireTapCoreTests` target declaration in Package.swift (build success is the test).

### AC-2: Network absent from production report
`WireTapReport` has no `add(network:)` method. A `WireTapSession` emitted by `exportData()`
always has `network: []`. No path through `WireTapReport` can produce a non-empty network array.
**Automated**: `WireTapReportSpec.test_AC2_networkAlwaysEmpty`

### AC-3: Device names anonymized at standard privacy level
Given a `BleEntry` with `device = "MS2-A1B2"`, `WireTapReport(privacy: .standard).build()` emits
a `BleRecord` where `device` equals `"***A1B2"` (last 4 chars, `***` prefix).
**Automated**: `WireTapReportSpec.test_AC3_deviceNameTruncated`

### AC-4: Decoder runs in release path
A decoder registered via `report.registerDecoder(forCharacteristic:_:)` is called during
`build()`, and its output named fields appear in the emitted `BleRecord.decodedFields`.
**Automated**: `WireTapReportSpec.test_AC4_decoderRunsOnBuild`

### AC-5: Format compatible with debug export
A `WireTapSession` built by `WireTapReport` from a known set of BLE + NFC entries is
byte-compatible with a session built by the debug path (`WireTap.makeSession()`) from the same
entries (BLE + NFC only). Schema version, field names, and timestamp format must match.
**Automated**: `WireTapReportSpec.test_AC5_formatParityWithDebugSession`

### AC-6: No disk write, no persistent storage
After `WireTapReport.exportData()` returns, `FileManager.default.urls(for:in:)` shows no new
files. The report directory (if any) is empty. Verified by scanning tmp + documents after export.
**Automated**: `WireTapReportSpec.test_AC6_noFilesWritten`

### AC-7: DEBUG path unchanged
All 75 existing tests on the `WireTap` (Inspector) target pass without source changes.
**Automated**: `npm test` equivalent — `swift test --target WireTapTests` (75 pass).

### AC-8: Umbrella import works
An app file containing only `import WireTap` (no `import WireTapCore`) can reference
`WireTapReport`, `BleDecoderRegistry`, `WireTapPrivacyLevel`, and all previously-public symbols.
**Automated**: compile-time — added to the existing `WireTapTests` smoke test.

---

## 9. Out of scope

- The MS2 troubleshooter UI, health checks, or the BLE log history collection — those are
  MS2-FEAT-004's responsibility.
- Network data in any production path — excluded permanently from `WireTapReport`.
- Automatic consent dialogs or privacy banners — the consuming app owns UX and consent.
- Privacy manifest (`PrivacyInfo.xcprivacy`) changes for WireTap itself — not needed.
- New decoders, new BLE/NFC event types, or changes to the `.wiretapsession` schema.
- Remote/cloud export, push to backend — `WireTapReport` produces `Data`; what the app does
  with it is entirely outside this spec.

---

## 10. Implementation sequence

1. **Update `doc/specs/README.md`** — add TRACER-013 to the feature index.
2. **Create directories**: `Sources/WireTapCore/`, `Sources/WireTapInspector/`,
   `Tests/WireTapCoreTests/`.
3. **Move files** (no edits): `Core/` → `WireTapCore/`; `Views/` + `Overlay/` +
   `Interceptors/` → `WireTapInspector/`.
4. **Update `Package.swift`** — two targets, two products (§4.2).
5. **Add umbrella re-export** — `WireTapInspector/WireTap+Umbrella.swift`.
6. **Move test files** to `WireTapCoreTests/`; update `@testable import WireTap` →
   `@testable import WireTapCore` in moved files.
7. **Add `BleDecoderRegistry` protocol** + `extension BleStore: BleDecoderRegistry {}` in
   `BleEntry.swift` or a new `BleDecoderRegistry.swift`.
8. **Add `WireTapPrivacyLevel` enum** to `Sources/WireTapCore/`.
9. **Implement `WireTapReport`** in `Sources/WireTapCore/WireTapReport.swift`.
10. **Write `WireTapReportSpec`** — AC-2 through AC-6.
11. **Verify** all 75 existing tests pass on `WireTap` target — AC-7, AC-8.
12. **Bump version** to `1.1.0` in Package.swift and CHANGELOG.md.
