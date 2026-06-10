// swift-tools-version:5.10
// WireTap — drop-in, in-app HTTP / BLE / NFC debug inspector for iOS apps.
// See README.md for integration guide and architecture overview.
import PackageDescription

let package = Package(
    name: "WireTap",
    platforms: [
        .iOS(.v16),
        .macOS(.v14)
    ],
    products: [
        // Full DEBUG inspector: capture + views + overlay. Depends on WireTapCore.
        .library(name: "WireTap",     targets: ["WireTap"]),
        // Release-safe serialization / export slice. No capture, no UI.
        .library(name: "WireTapCore", targets: ["WireTapCore"]),
    ],
    targets: [
        // MARK: WireTapCore — models, serialization, redaction, decoders, LLM renderer.
        // Safe to link in release builds. Zero SwiftUI/UIKit dependency (one guarded canImport).
        .target(
            name: "WireTapCore",
            path: "Sources/WireTapCore"
        ),

        // MARK: WireTap — SwiftUI inspector UI, floating overlay, URLProtocol interceptor.
        // Depends on WireTapCore and re-exports it so `import WireTap` is unchanged.
        .target(
            name: "WireTap",
            dependencies: ["WireTapCore"],
            path: "Sources/WireTapInspector"
        ),

        // MARK: Tests
        .testTarget(
            name: "WireTapCoreTests",
            dependencies: ["WireTapCore"],
            path: "Tests/WireTapCoreTests"
        ),
        .testTarget(
            name: "WireTapTests",
            dependencies: ["WireTap"],
            path: "Tests/WireTapTests"
        ),
    ]
)
