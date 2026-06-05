# WireTap

[![CI](https://github.com/karkipsn/WireTap/actions/workflows/ci.yml/badge.svg)](https://github.com/karkipsn/WireTap/actions/workflows/ci.yml)
[![Swift 5.10](https://img.shields.io/badge/Swift-5.10-orange.svg)](https://swift.org)
[![Platforms iOS 16+ | macOS 14+](https://img.shields.io/badge/Platforms-iOS%2016%2B%20%7C%20macOS%2014%2B-blue.svg)](#requirements)
[![SPM compatible](https://img.shields.io/badge/SPM-compatible-brightgreen.svg)](#installation)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

A **drop-in, in-app debug inspector** for iOS apps — captures HTTP traffic, BLE events, and NFC events with a live SwiftUI inspector UI, reachable from anywhere via a Chucker-style floating bubble. Zero overhead in production builds.

Standalone Swift package: no dependency on your app's types. Works in any iOS app — **SwiftUI, UIKit, or hybrid** (React Native, Flutter, Capacitor). Architecture mirrors Android's Chucker + BLE/NFC logging: the SDK/data layer stays completely unaware of WireTap; the app layer wires everything up at startup.

**Two ways to show the inspector:**
- **Floating bubble** — `WireTap.installFloatingButton()` once at startup → reachable from any screen.
- **Embedded view** — drop `WireTapView()` into your own debug navigation.

By default the inspector shows **Network only**; opt into `.ble` / `.nfc` per app.

---

## Contents

- [Architecture](#architecture)
- [Requirements](#requirements)
- [Capabilities & status](#capabilities--status)
- [Installation](#installation)
- [Quick Start](#quick-start)
- [Integration Tutorials](#integration-tutorials)
  - [Add the package — Swift Package Manager](#1-add-the-package--swift-package-manager)
  - [Add the package — XcodeGen](#2-add-the-package--xcodegen)
  - [SwiftUI app](#3-swiftui-app)
  - [UIKit app](#4-uikit-app)
  - [Hybrid apps (React Native / Flutter / Capacitor)](#5-hybrid-apps-react-native--flutter--capacitor)
- [Network Interception](#network-interception)
- [BLE Observation](#ble-observation)
- [NFC Observation](#nfc-observation)
- [Inspector UI](#inspector-ui)
- [Observer Protocol Reference](#observer-protocol-reference)
- [Entry Type Reference](#entry-type-reference)
- [SDK Extraction Guide](#sdk-extraction-guide)
- [Contributing](#contributing)
- [License](#license)

---

## Architecture

```
SDK / Data Layer                App Layer (#if DEBUG)       WireTap Package
────────────────────            ─────────────────────       ──────────────
BleEventObserver (protocol) ←── BleWireTapObserver ─────────▶ WireTap.ble
NfcEventObserver (protocol) ←── NfcWireTapObserver ─────────▶ WireTap.nfc
AppApiClient                    AppContainer ───────────────▶ WireTapURLProtocol
  └ takes URLSessionConfig                                      └ WireTap.network
```

**Key principle:** The SDK/Data layer defines observer protocols and accepts injectable configuration. It has zero knowledge of WireTap. Concrete observers and protocol registrations live only in the app layer, fully compiled out in release builds.

This matches OkHttp's `EventListener` pattern on Android and `URLProtocol` on iOS.

---

## Requirements

- **iOS 16+** — the product target. The inspector UI, floating bubble, and all capture run here.
- **macOS 14+** — a **build/test target only**, so the package compiles and runs its test
  suite via `swift test` on the command line (fast, no simulator). WireTap is **not** intended
  as a shipping macOS app; UIKit-only features (share sheet, floating bubble) are compiled out
  on macOS. Any iOS build — native, React Native, or Flutter — gets the full feature set.
- Swift 5.10+ / Xcode 15+

---

## Capabilities & status

Transparent view of what's here today, so you can plan around it.

| Capability | Status | Notes |
|------------|--------|-------|
| Network capture (your `URLSession`) | ✅ Stable | via `WireTapURLProtocol`; `Authorization` auto-redacted |
| BLE event capture | ✅ Stable | via `BleEventObserver`; 19 event types |
| NFC event capture | ✅ Stable | via `NfcEventObserver` |
| Inspector UI (Network / BLE / NFC tabs) | ✅ Stable | filters, search, hex/ASCII, cURL, share |
| **Unified Timeline tab** | ✅ New | cross-stream BLE+NFC+network, time-ordered (TRACER-002) |
| **Session persistence** (survives relaunch) | ✅ New | opt-in `WireTap.configure(storage: .disk())` (TRACER-001) |
| **Session export / import** (`.wiretapsession`) | ✅ New | "Export Session…" — share sheet on iOS (TRACER-002) |
| **LLM export** ("Copy for AI") | ✅ New | compact, redacted, token-bounded (TRACER-003) |
| **AI-agent access over MCP** | 🟡 Companion | `wiretap-mcp` Node server reads exported sessions (file mode) |
| **Pluggable BLE decoders** (raw bytes → named fields) | ✅ New | `WireTap.ble.registerDecoder(forCharacteristic:)` (TRACER-005) |
| **Configurable redaction** (headers + JSON body keys) | ✅ New | `WireTap.redaction` (TRACER-010); defaults cover auth/token/secret |
| Live MCP bridge (query while running) | ◻️ Planned | TRACER-004 phase 2 |
| Connection lifecycle view, cross-radio correlation | ◻️ Planned | TRACER-006…007 |

Redaction is a hard invariant: secrets are scrubbed before anything is persisted, exported,
or handed to an agent — sensitive **headers and JSON body keys** (configurable via
`WireTap.redaction`, TRACER-010). The new UI features compile cross-platform but are **verified by build,
on-device manual check pending** (SwiftUI views aren't unit-tested). The capture/export/persist
logic underneath is covered by the test suite.

See [`doc/specs/`](doc/specs/) for the roadmap and per-feature acceptance criteria.

---

## Installation

Add WireTap remotely from GitHub or as a local path dependency — see the recipes below.

### Package.swift

```swift
dependencies: [
    .package(path: "LocalPackages/WireTap"),
],
targets: [
    .target(
        name: "MyApp",
        dependencies: [
            .product(name: "WireTap", package: "WireTap"),
            // ...
        ]
    )
]
```

### Xcode project

Add via **File › Add Package Dependencies › Add Local…** and point to `LocalPackages/WireTap`.

---

## Quick Start

Wire everything in one place — your app's composition root (`AppContainer` or `@main App`).

```swift
// AppContainer.swift

#if DEBUG
import WireTap
#endif

@MainActor
final class AppContainer {
    init() {
        let ble = AppBleManager()
        let nfc = NfcManager()

        // 1. Network — inject WireTapURLProtocol into the URLSession config
        #if DEBUG
        let urlConfig = WireTapURLProtocol.makeSessionConfiguration(
            requestTimeout: 15,
            resourceTimeout: 30
        )
        let apiClient = AppApiClient(configuration: urlConfig)
        #else
        let apiClient = AppApiClient()
        #endif

        // 2. BLE — attach observer
        #if DEBUG
        ble.eventObserver = BleWireTapObserver()
        #endif

        // 3. NFC — attach observer
        #if DEBUG
        nfc.eventObserver = NfcWireTapObserver()
        #endif
    }
}
```

> In production builds, `eventObserver` is `nil` on every manager — every call site is a free no-op. No code is compiled in from WireTap.

---

## Integration Tutorials

Step-by-step recipes for the common ways to consume WireTap. Every recipe is two parts:
**(A) add the package**, then **(B) install the inspector** (bubble and/or embedded view) plus
optional network capture.

The minimal integration is genuinely two lines:

```swift
import WireTap
// once, after the scene is active, in DEBUG:
WireTap.installFloatingButton()
```

That alone gives you the floating bubble → Network inspector. Everything below is about
*wiring data in* (network/BLE/NFC) and *where* to place that one call per app type.

---

### 1. Add the package — Swift Package Manager

**Remote (recommended for sharing across apps):**

```swift
// Package.swift
dependencies: [
    .package(url: "https://github.com/karkipsn/WireTap.git", from: "1.0.0"),
],
targets: [
    .target(name: "MyApp", dependencies: [
        .product(name: "WireTap", package: "WireTap"),
    ]),
]
```

**Local path (monorepo / vendored):**

```swift
dependencies: [ .package(path: "LocalPackages/WireTap") ],
```

**In an `.xcodeproj` (no Package.swift):** File › Add Package Dependencies → enter the Git URL
(or **Add Local…** for a path), then add the **WireTap** library to your app target.

> Tip: keep WireTap out of release if you want zero binary footprint — link it normally but gate
> every WireTap call site behind `#if DEBUG`. The package is small and has no third-party deps, so
> linking it in release is also fine if you prefer runtime gating.

---

### 2. Add the package — XcodeGen

In `project.yml`:

```yaml
packages:
  WireTap:
    # local path…
    path: LocalPackages/WireTap
    # …or remote:
    # url: https://github.com/karkipsn/WireTap.git
    # from: 1.0.0

targets:
  MyApp:
    type: application
    platform: iOS
    dependencies:
      - package: WireTap
        product: WireTap
```

Then regenerate:

```bash
xcodegen generate
```

> Always re-run `xcodegen generate` after editing `project.yml` or adding source files, then reopen
> the generated `.xcodeproj`.

---

### 3. SwiftUI app

**B1 — Install the floating bubble** at the app root. `.onAppear` runs once the scene is live,
which is exactly when the overlay window can attach:

```swift
import SwiftUI
#if DEBUG
import WireTap
#endif

@main
struct MyApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
                #if DEBUG
                .onAppear { WireTap.installFloatingButton(tabs: .all) }   // Timeline + Network + BLE + NFC
                #endif
        }
    }
}
```

**B2 — Or embed the view** in your own debug screen instead of (or in addition to) the bubble:

```swift
#if DEBUG
NavigationLink("Network Inspector") {
    WireTapView()                      // Network only
}
#endif
```

**Network capture** — build your `URLSession` from a WireTap-configured `URLSessionConfiguration`:

```swift
#if DEBUG
let session = URLSession(configuration: WireTapURLProtocol.makeSessionConfiguration())
#else
let session = URLSession(configuration: .default)
#endif
```

---

### 4. UIKit app

**B1 — Install the bubble** in your `SceneDelegate` (or `AppDelegate` for pre-scene apps):

```swift
// SceneDelegate.swift
import WireTap

func scene(_ scene: UIScene, willConnectTo session: UISceneSession,
           options: UIScene.ConnectionOptions) {
    // … your window setup …
    #if DEBUG
    WireTap.installFloatingButton(tabs: [.network, .ble])
    #endif
}
```

**B2 — Or present the inspector** from any debug button using `UIHostingController`:

```swift
import SwiftUI
import WireTap

@objc func showWireTap() {
    let host = UIHostingController(rootView: NavigationStack { WireTapView() })
    present(host, animated: true)
}
```

**Network capture** — same as SwiftUI: create your `URLSession` with
`WireTapURLProtocol.makeSessionConfiguration()`.

---

### 5. Hybrid apps (React Native / Flutter / Capacitor)

A React Native or Flutter app **is a native iOS app** underneath — it has an `AppDelegate`,
and WireTap links into that iOS build like any SPM/CocoaPods dependency. Because those builds
are UIKit-based, `canImport(UIKit)` is true and they get the **full iOS feature set** (bubble,
inspector, share sheet) — the macOS fallback never applies to them.

**What works out of the box vs. what needs a bridge** — be clear-eyed about this before you start:

| Signal | Native iOS | RN / Flutter | What to do for hybrid |
|--------|------------|--------------|-----------------------|
| Floating bubble + inspector UI | ✅ | ✅ | Call `WireTap.installFloatingButton()` from the delegate |
| BLE / NFC events | ✅ | ✅ *if native owns the radio* | Wire `BleEventObserver`/`NfcEventObserver` in the native plugin (most BLE plugins are native) |
| Network — your `URLSession` | ✅ | ⚠️ rarely applies | JS/Dart HTTP doesn't use your `URLSession` |
| Network — JS/Dart HTTP (fetch/axios/Dio) | n/a | ⚠️ needs bridge | Forward each request from a JS/Dart interceptor to `WireTap.network.record(...)` (below) |
| Session export / LLM "Copy for AI" / persistence | ✅ | ✅ | Same API; no extra work |

The bubble is a plain `UIWindow`, so it floats above the RN/Flutter render surface from any screen.

**React Native** — in `AppDelegate.swift` (or via a bridging header from `AppDelegate.m`):

```swift
import WireTap

func application(_ application: UIApplication,
                 didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
    #if DEBUG
    // Defer to next runloop so the RN root window exists first.
    DispatchQueue.main.async { WireTap.installFloatingButton() }
    #endif
    return true
}
```

**Flutter** — in `ios/Runner/AppDelegate.swift`:

```swift
import WireTap

override func application(_ application: UIApplication,
                          didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
    #if DEBUG
    DispatchQueue.main.async { WireTap.installFloatingButton() }
    #endif
    GeneratedPluginRegistrant.register(with: self)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
}
```

**Capacitor / Cordova** — same idea in `AppDelegate.swift`’s `didFinishLaunchingWithOptions`.

**Capturing network traffic in hybrid apps.** The JS/Dart HTTP layer (fetch, axios, Dio,
`OkHttp`-on-Android) does not flow through a `URLSession` you can configure, so
`makeSessionConfiguration()` won't see it. Two reliable options:

1. **Native `URLSession.shared`-based traffic** — register globally:
   ```swift
   #if DEBUG
   URLProtocol.registerClass(WireTapURLProtocol.self)   // catches URLSession.shared & URLConnection
   #endif
   ```
   This covers some native modules but **not** custom sessions a framework creates internally.

2. **Record from a JS/Dart interceptor via a tiny native bridge** (universal). Add an interceptor
   in your app code that forwards each request to native, which calls `WireTap.network.record(...)`:

   ```swift
   // A Capacitor plugin / RN native module / Flutter MethodChannel handler:
   @objc func logRequest(_ call: CAPPluginCall) {
       Task { @MainActor in
           WireTap.network.record(NetworkEntry(
               method: call.getString("method") ?? "GET",
               url: call.getString("url") ?? "",
               requestHeaders: call.getObject("headers") as? [String: String] ?? [:],
               requestBody: call.getString("body"),
               statusCode: call.getInt("status"),
               responseBody: call.getString("response"),
               durationMs: call.getInt("durationMs") ?? 0
           ))
       }
   }
   ```

   ```js
   // JS side — an axios interceptor (sketch):
   axios.interceptors.response.use(res => {
     WireTap.logRequest({ method: res.config.method, url: res.config.url,
                         status: res.status, durationMs: /* timing */ 0 });
     return res;
   });
   ```

> BLE/NFC in hybrid apps: if the native side owns the radios (most BLE plugins do), wire the
> `BleEventObserver` / `NfcEventObserver` bridges in native code exactly as in [BLE Observation](#ble-observation)
> / [NFC Observation](#nfc-observation), and enable those tabs with `tabs: .all`.

---

## Network Interception

WireTap intercepts HTTP traffic via `WireTapURLProtocol`, a `URLProtocol` subclass. This is the iOS equivalent of an OkHttp interceptor — your API client code does not change.

### How it works

1. You inject a `URLSessionConfiguration` that has `WireTapURLProtocol` pre-registered.
2. Every request going through that `URLSession` is intercepted, logged to `WireTap.network`, and forwarded transparently.
3. Authorization headers are automatically redacted (`Bearer [redacted]`).

### Setup

```swift
// App layer — #if DEBUG
import WireTap

let config = WireTapURLProtocol.makeSessionConfiguration(
    requestTimeout: 15,   // seconds
    resourceTimeout: 30   // seconds
)
let client = AppApiClient(configuration: config)
```

### Factory method signature

```swift
public static func makeSessionConfiguration(
    requestTimeout: TimeInterval = 15,
    resourceTimeout: TimeInterval = 30
) -> URLSessionConfiguration
```

### Manually recording an entry

If you have a custom transport layer that doesn't use `URLSession` (e.g. a socket or gRPC channel):

```swift
import WireTap

await WireTap.network.record(NetworkEntry(
    method: "POST",
    url: "https://api.example.com/sessions",
    requestHeaders: ["Content-Type": "application/json"],
    requestBody: "{\"deviceId\": \"abc\"}",
    statusCode: 200,
    responseBody: "{\"sessionId\": \"xyz\"}",
    durationMs: 142
))
```

---

## BLE Observation

The `BleEventObserver` protocol is defined in the SDK/Data layer. Your BLE manager calls its methods at every meaningful event. WireTap provides `BleWireTapObserver` as the concrete implementation.

### Observer protocol (defined in SDK)

```swift
protocol BleEventObserver: AnyObject {
    func bleDidUpdateRadioState(poweredOn: Bool)
    func bleDidConnect(peripheralName: String?)
    func bleDidFailToConnect(peripheralName: String?, error: String)
    func bleDidDisconnect(peripheralName: String?, error: String?)
    func bleDidDiscoverService(uuid: String, characteristicNames: [String], mtu: Int)
    func bleDidReadCharacteristic(uuid: String, data: Data)
    func bleDidReceiveNotification(uuid: String, data: Data, label: String?)
    func bleDidWriteCharacteristic(uuid: String, error: String?)
    func bleDidStartPairing(peripheralName: String?)
    func bleDidCompletePairing(peripheralName: String?)
}
```

### Wiring (app layer)

```swift
// App layer — #if DEBUG
import WireTap

ble.eventObserver = BleWireTapObserver()
```

### How the manager calls hooks

```swift
// Inside AppBleManager — no WireTap import, no #if DEBUG
weak var eventObserver: BleEventObserver?

// In centralManager(_:didConnect:)
eventObserver?.bleDidConnect(peripheralName: peripheral.name)

// In peripheral(_:didUpdateValueFor:)
eventObserver?.bleDidReadCharacteristic(uuid: char.uuid.uuidString, data: data)
```

The `weak var` is `nil` in production — the Swift runtime eliminates the call entirely.

### Manually logging a BLE event

```swift
import WireTap

WireTap.ble.log(BleEntry(
    type: .notification,
    uuid: "6E400003-B5A3-F393-E0A9-E50E24DCCA9E",
    device: "Device-01",
    data: rawData
))
```

---

## NFC Observation

Same pattern as BLE. The `NfcEventObserver` protocol is in the SDK layer; `NfcWireTapObserver` is the WireTap-side concrete implementation.

### Observer protocol (defined in SDK)

```swift
protocol NfcEventObserver: AnyObject {
    func nfcDidStartScan(requireOobHandshake: Bool)
    func nfcDidDetectTag(technology: String)         // "ISO7816 / NFC Forum Type 4" or "MiFare (NFC-A/B)"
    func nfcDidReadNdef(recordCount: Int)
    func nfcDidParseRecord(mimeType: String, payload: Data)
    func nfcDidDecodeIosTrust(deviceId: String, hasCert: Bool, serviceUuid: String?)
    func nfcDidComplete(deviceName: String)
    func nfcDidFail(error: String)
}
```

### Wiring (app layer)

```swift
// App layer — #if DEBUG
import WireTap

nfc.eventObserver = NfcWireTapObserver()
```

### Manually logging an NFC event

```swift
import WireTap

WireTap.nfc.log(NfcEntry(
    type: .recordParsed,
    descriptor: "application/vnd.example.addr",
    data: payload
))
```

---

## Inspector UI

`WireTapView` is the root SwiftUI inspector. Drop it anywhere in your debug navigation stack.

```swift
// In your debug menu / settings screen
#if DEBUG
import WireTap

NavigationLink("WireTap Inspector") {
    WireTapView()
}
#endif
```

`WireTapView` has three tabs — **Network**, **BLE**, **NFC** — each with a live badge showing the entry count.

### Floating bubble (drop-in, no navigation needed)

For a Chucker-style overlay that's reachable from **any** screen — even before your app's
settings/menu exist (e.g. a failed login or pairing) — install the floating bubble once at
startup. It lives in its own passthrough window above everything (tab bars, sheets,
onboarding), and touches outside the bubble fall straight through to your app.

```swift
#if DEBUG
import WireTap

// Anywhere after the scene is active (e.g. root view .onAppear, or SceneDelegate):
WireTap.installFloatingButton()                          // Network only (default)
WireTap.installFloatingButton(tabs: [.ble])              // just BLE
WireTap.installFloatingButton(tabs: [.network, .nfc])   // any two, in this tab order
WireTap.installFloatingButton(tabs: .all)               // all three (= [.network, .ble, .nfc])
#endif
```

The bubble opens **WireTap's own UI only** — keep your app's debug menu separate.

**Choosing tabs is entirely the dev's call** — pass any combination of `.network`, `.ble`,
`.nfc` in an ordered array (one, two, or all three). The array order is the tab order;
duplicates are ignored; an empty array falls back to `.network`. Convenience selectors:
`.all` and `WireTapTab.allCases`. With a single tab the segmented bar is hidden and that view
fills the screen.

Works in any native or hybrid app (UIKit, SwiftUI, React Native, Flutter, Capacitor…) that
links the package — there's no dependency on your app's types. Drag the bubble to reposition;
tap to open; the inspector presents with a built-in close button.

Point it at your own diagnostics screen instead of `WireTapView` (it may still embed
`WireTapView`):

```swift
WireTap.installFloatingButton(systemImage: "stethoscope") {
    MyAppDebugScreen()        // pass a plain screen — the overlay wraps it in a NavigationStack
}
```

Remove it (e.g. when toggling a debug setting off):

```swift
WireTap.removeFloatingButton()
```

> The bubble is iOS-only and intended for DEBUG builds — gate the call with `#if DEBUG` so it
> compiles out of release, matching the rest of WireTap.

### Features per tab

| Tab | Features |
|-----|----------|
| **Timeline** | Unified BLE+NFC+network events in time order; per-kind filter chips; color coded by stream. The cross-radio view no network-only inspector offers. |
| **Network** | Method filter chips, search by URL/status, status color coding (green/orange/red), tap for full request+response+cURL detail, copy per-block, share sheet |
| **BLE** | Event type filter chips, search by UUID/device/detail, color coded by event class (connect=green, error=red, data=blue/orange), hex+ASCII payload view, share |
| **NFC** | Event type filter chips, search by MIME type/detail, hex+ASCII payload, share |

Each inspector's toolbar menu also offers **Copy for AI** (LLM-ready text → pasteboard) and
**Export Session…** (`.wiretapsession` bundle → share sheet on iOS).

### Clearing data

```swift
// Clear a single store
WireTap.network.clear()
WireTap.ble.clear()
WireTap.nfc.clear()

// Clear all at once
WireTap.clearAll()
```

### Configuring retention limits

```swift
WireTap.network.maxEntries = 500  // default 500
WireTap.ble.maxEntries     = 1000 // default 1000
WireTap.nfc.maxEntries     = 200  // default 200
```

Oldest entries are dropped automatically when the limit is reached.

---

## Observer Protocol Reference

### `BleEventObserver`

All methods called on the main actor from `AppBleManager`.

| Method | When called |
|--------|-------------|
| `bleDidUpdateRadioState(poweredOn:)` | `CBCentralManager` state changes to `.poweredOn` or `.poweredOff/.unauthorized` |
| `bleDidConnect(peripheralName:)` | `centralManager(_:didConnect:)` |
| `bleDidFailToConnect(peripheralName:error:)` | `centralManager(_:didFailToConnect:error:)` |
| `bleDidDisconnect(peripheralName:error:)` | `centralManager(_:didDisconnectPeripheral:error:)` |
| `bleDidDiscoverService(uuid:characteristicNames:mtu:)` | All required characteristics discovered; connection marked `.connected` |
| `bleDidReadCharacteristic(uuid:data:)` | `peripheral(_:didUpdateValueFor:)` responding to an explicit read |
| `bleDidReceiveNotification(uuid:data:label:)` | `peripheral(_:didUpdateValueFor:)` delivering a notification; `label` is `"auth response"` during app-layer auth |
| `bleDidWriteCharacteristic(uuid:error:)` | `peripheral(_:didWriteValueFor:error:)` |
| `bleDidStartPairing(peripheralName:)` | Just before encrypted read triggers LESC Just Works |
| `bleDidCompletePairing(peripheralName:)` | After 5-second LESC completion window |

### `NfcEventObserver`

All methods called on the main actor from `NfcManager`.

| Method | When called |
|--------|-------------|
| `nfcDidStartScan(requireOobHandshake:)` | `beginScan()` entered |
| `nfcDidDetectTag(technology:)` | Tag type identified in `handleTag` — before NDEF operations begin |
| `nfcDidReadNdef(recordCount:)` | `parseDeviceInfo(from:)` called with a set of records |
| `nfcDidParseRecord(mimeType:payload:)` | Each record in the NDEF message, before the switch |
| `nfcDidDecodeIosTrust(deviceId:hasCert:serviceUuid:)` | IosTrust proto successfully decoded |
| `nfcDidComplete(deviceName:)` | `complete(with: .success(_))` |
| `nfcDidFail(error:)` | `complete(with: .error(_))` or early exit in `beginScan` |

---

## Entry Type Reference

### `NetworkEntry`

| Property | Type | Description |
|----------|------|-------------|
| `method` | `String` | HTTP verb (GET, POST, …) |
| `url` | `String` | Full URL |
| `requestHeaders` | `[String: String]` | Authorization is always redacted |
| `requestBody` | `String?` | JSON body or nil |
| `statusCode` | `Int?` | HTTP status; nil on network error |
| `responseHeaders` | `[String: String]` | Response headers |
| `responseBody` | `String?` | Response JSON/text or nil |
| `durationMs` | `Int` | Round-trip time in milliseconds |
| `error` | `String?` | Network-level error message |
| `isSuccess` | `Bool` | `statusCode` in 200–299 |
| `curlCommand` | `String` | Reconstructed cURL invocation |

### `BleEntry`

| Property | Type | Description |
|----------|------|-------------|
| `type` | `BleEventType` | One of 18 event types |
| `uuid` | `String?` | Service or characteristic UUID |
| `device` | `String?` | Peripheral name |
| `data` | `Data?` | Raw payload bytes |
| `detail` | `String?` | Human-readable summary |
| `error` | `String?` | Error message for error events |
| `hexString` | `String?` | Computed: space-separated hex |
| `asciiString` | `String?` | Computed: printable ASCII, `.` for non-printable |

**`BleEventType` cases:** `connected`, `disconnected`, `connecting`, `reconnecting`, `serviceDiscovered`, `characteristicRead`, `characteristicWrite`, `notification`, `indication`, `pairingStarted`, `pairingSuccess`, `pairingFailed`, `authStarted`, `authSuccess`, `authFailed`, `mtuNegotiated`, `rssi`, `error`, `info`

### `NfcEntry`

| Property | Type | Description |
|----------|------|-------------|
| `type` | `NfcEventType` | One of 10 event types |
| `descriptor` | `String?` | MIME type or tag technology string |
| `detail` | `String?` | Human-readable summary |
| `data` | `Data?` | NDEF record payload bytes |
| `error` | `String?` | Error message for failed events |
| `hexString` | `String?` | Computed: space-separated hex |
| `asciiString` | `String?` | Computed: printable ASCII, `.` for non-printable |

**`NfcEventType` cases:** `scanStarted`, `tagDetected`, `ndefRead`, `recordParsed`, `iosTrustDecoded`, `apduSent`, `apduReceived`, `scanCompleted`, `scanFailed`, `cancelled`

---

## SDK Extraction Guide

When the Data/API layer is extracted into a standalone Swift package:

1. **Make protocols public.** `BleEventObserver` and `NfcEventObserver` are currently `internal`. Mark them `public` — they become part of the SDK's public API surface.

2. **Move `BleWireTapObserver` and `NfcWireTapObserver`** from the app target into a separate `WireTapAdapters` package (or keep them in the app target). They reference both the SDK protocols and WireTap types, so they are the correct glue layer.

3. **`WireTapURLProtocol` stays in this package.** It only depends on Foundation and WireTap's own `NetworkEntry` / `NetworkStore` — no SDK types.

4. **No changes required in the SDK itself.** `AppBleManager`, `NfcManager`, and `AppApiClient` already have zero WireTap dependencies. The `weak var eventObserver` pattern and injectable `URLSessionConfiguration` are production-grade extensibility points, not debug hacks.

5. **App-layer wiring stays identical.** `AppContainer` continues to be the single place that imports WireTap and connects everything.

```
After extraction:

Your SDK (public)            App layer (#if DEBUG)        WireTap (local pkg)
─────────────────            ─────────────────────        ──────────────────
BleEventObserver (public) ←── BleWireTapObserver ─────────▶ BleStore
NfcEventObserver (public) ←── NfcWireTapObserver ─────────▶ NfcStore
AppApiClient                  AppContainer ───────────────▶ WireTapURLProtocol
                                                              └ NetworkStore
```

---

## Contributing

Contributions are welcome — bug reports, feature requests, and pull requests. Please read
[CONTRIBUTING.md](CONTRIBUTING.md) before opening a PR. In short:

- Run `swift build` and `swift test` before pushing — the suite must stay green.
- Keep the package dependency-free (Foundation / SwiftUI only) and the SDK layer unaware of WireTap.
- Redaction is a hard invariant: never let a change leak secrets into persisted, exported, or LLM output.

By participating you agree to abide by the [Code of Conduct](CODE_OF_CONDUCT.md).

---

## License

WireTap is released under the **MIT License**. See [LICENSE](LICENSE) for the full text.

Copyright © 2026 Poshan Karki.
