// MARK: - TRACER-013: WireTapPrivacyLevel

/// Controls how BLE device identifiers appear in a `WireTapReport` export.
///
/// Use `.standard` in all production / release build paths. `.verbose` is
/// available for DEBUG tooling only and must be guarded at the call site.
public enum WireTapPrivacyLevel: Sendable {
    /// Device names are anonymized: only the last 4 characters are kept,
    /// prefixed with `***` (e.g. `"MS2-A1B2"` → `"***A1B2"`).
    /// Characteristic UUIDs are kept in full — they identify protocols, not people.
    /// This is the only option safe for production / App Store release builds.
    case standard

    /// Full device names are included. Never use in a release build path.
    case verbose
}
