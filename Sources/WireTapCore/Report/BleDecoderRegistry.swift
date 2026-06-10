import Foundation

// MARK: - TRACER-013: BleDecoderRegistry protocol

/// Anything that can accept BLE characteristic decoders.
///
/// `BleStore` and `WireTapReport` both conform, so a decoder helper that takes
/// `any BleDecoderRegistry` works on both the DEBUG capture path and the
/// release diagnostic path without a source change at the call site.
///
/// Example:
/// ```swift
/// // DEBUG:
/// Ms2Decoders.registerAll(on: WireTap.ble)   // BleStore
/// // Release:
/// Ms2Decoders.registerAll(on: report)        // WireTapReport
/// ```
@MainActor
public protocol BleDecoderRegistry: AnyObject {
    /// Register a decoder for a BLE characteristic UUID.
    /// The closure is called with the raw payload bytes and must return named
    /// string fields (e.g. `["version": "2.1", "status": "ok"]`).
    /// Matching is case-insensitive. An empty result is treated as no decode.
    func registerDecoder(
        forCharacteristic uuid: String,
        _ decode: @escaping @Sendable (Data) -> [String: String]
    )
}

// MARK: - BleStore retroactive conformance

extension BleStore: BleDecoderRegistry {}
