# Contributing to WireTap

Thanks for your interest in improving WireTap! Bug reports, feature requests, and pull
requests are all welcome.

## Ground rules

WireTap has a few hard constraints. A change that breaks any of these will not be merged:

1. **No third-party dependencies.** The package depends only on Apple frameworks
   (Foundation, SwiftUI, Combine, CoreBluetooth/NFC types as needed). Adding an external
   dependency defeats the "drop-in, zero-friction" promise.
2. **The SDK / data layer stays unaware of WireTap.** Capture happens through observer
   protocols (`BleEventObserver`, `NfcEventObserver`) and an injectable
   `URLSessionConfiguration`. Production code paths must compile to no-ops when WireTap is absent.
3. **Redaction is a hard invariant.** Secrets (auth headers, configured JSON body keys) must
   be scrubbed *before* anything is persisted, exported, or handed to an LLM/MCP. Any change
   touching capture, export, or persistence must preserve this — add a `RedactionSpec` case if
   you touch a new sink.
4. **Keep it cross-platform.** The package builds for iOS 16+ and macOS 14+ (the macOS target
   is build/test only). UIKit-only features must be gated behind `canImport(UIKit)`.

## Development workflow

```bash
swift build      # compile
swift test       # run the full test suite (must stay green)
```

- New features follow the spec-first workflow: add a `doc/specs/TRACER-NNN-<slug>.md` describing
  the feature and its acceptance criteria, then add the matching `*Spec.swift` tests under
  `Tests/WireTapTests/`, then implement until green.
- SwiftUI views are not unit-tested; verify them by build + on-device/simulator manual check and
  note that in the PR.
- Match the surrounding code style — naming, comment density, and idioms.

## Submitting a pull request

1. Fork the repo and create a feature branch.
2. Make your change with tests; ensure `swift build` and `swift test` both pass.
3. Update `CHANGELOG.md` under the `[Unreleased]` heading.
4. Open the PR with a clear description of the problem and your approach.

## Reporting bugs

Open an issue with: what you did, what you expected, what happened, and (if relevant) a minimal
`.wiretapsession` export or code snippet that reproduces it. Make sure any attached export is
already redacted.

By contributing you agree that your contributions are licensed under the
[MIT License](LICENSE) and that you abide by the [Code of Conduct](CODE_OF_CONDUCT.md).
