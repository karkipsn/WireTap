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
        .library(name: "WireTap", targets: ["WireTap"])
    ],
    targets: [
        .target(
            name: "WireTap",
            path: "Sources/WireTap"
        ),
        .testTarget(
            name: "WireTapTests",
            dependencies: ["WireTap"],
            path: "Tests/WireTapTests"
        )
    ]
)
