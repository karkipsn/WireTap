#if os(iOS)
import SwiftUI
import UIKit

// MARK: - Public API

public extension WireTap {

    /// Installs a floating, draggable debug bubble that opens the WireTap inspector.
    ///
    /// The bubble lives in its own passthrough window above every screen — onboarding,
    /// tab bars, even presented sheets — so the inspector is reachable from anywhere in
    /// any native or hybrid app that links this package. One call, no UI plumbing:
    ///
    /// ```swift
    /// #if DEBUG
    /// WireTap.installFloatingButton()        // opens WireTapView (Network / BLE / NFC)
    /// #endif
    /// ```
    ///
    /// Idempotent — calling it again while already installed is a no-op.
    /// - Parameters:
    ///   - systemImage: SF Symbol for the bubble. Defaults to a ladybug.
    ///   - tabs: Categories the inspector shows. Defaults to `[.network]`; pass
    ///           `[.network, .ble, .nfc]` (or any subset) for apps that capture more.
    ///   - scene: Window scene to attach to. Defaults to the active foreground scene.
    @MainActor
    static func installFloatingButton(systemImage: String = "ladybug.fill",
                                      tabs: [WireTapTab] = [.network],
                                      in scene: UIWindowScene? = nil) {
        installFloatingButton(systemImage: systemImage, in: scene) { WireTapView(tabs: tabs) }
    }

    /// Installs the floating bubble, opening a **custom** inspector instead of `WireTapView`.
    ///
    /// Useful when the host app wants its own diagnostics root (which may itself embed
    /// `WireTapView`). The inspector is presented inside a `NavigationStack` with a close
    /// button supplied by the overlay — so pass a plain screen, not your own stack.
    ///
    /// ```swift
    /// WireTap.installFloatingButton { MyAppDebugScreen() }
    /// ```
    @MainActor
    static func installFloatingButton<Inspector: View>(
        systemImage: String = "ladybug.fill",
        in scene: UIWindowScene? = nil,
        @ViewBuilder inspector: @escaping () -> Inspector
    ) {
        WireTapOverlay.install(systemImage: systemImage, scene: scene) { AnyView(inspector()) }
    }

    /// Removes the floating bubble and tears down its window.
    @MainActor
    static func removeFloatingButton() {
        WireTapOverlay.remove()
    }
}

// MARK: - Overlay controller

@MainActor
enum WireTapOverlay {
    private static var window: WireTapPassthroughWindow?

    static func install(systemImage: String, scene: UIWindowScene?, inspector: @escaping () -> AnyView) {
        guard window == nil else { return }
        guard let scene = scene ?? activeScene() else { return }

        let state = BubbleState()
        let w = WireTapPassthroughWindow(windowScene: scene)
        w.bubbleState = state
        w.windowLevel = .alert + 1
        w.backgroundColor = .clear
        let host = UIHostingController(
            rootView: WireTapBubbleRootView(systemImage: systemImage, state: state, inspector: inspector)
        )
        host.view.backgroundColor = .clear
        w.rootViewController = host
        w.isHidden = false
        window = w
    }

    static func remove() {
        window?.isHidden = true
        window = nil
    }

    private static func activeScene() -> UIWindowScene? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        return scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
    }
}

// MARK: - Passthrough window

/// Lets touches fall through to the app below — capturing them only inside the bubble's
/// frame, or while the inspector sheet is presented (then it acts as a normal modal host).
///
/// SwiftUI processes gestures at the hosting-view level, so a per-view identity check in
/// `hitTest` can't tell "tapped the bubble" from "tapped empty space" (both resolve to the
/// hosting view). Hence the explicit frame test fed by `BubbleState`.
final class WireTapPassthroughWindow: UIWindow {
    var bubbleState: BubbleState?

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        if rootViewController?.presentedViewController != nil {
            return super.hitTest(point, with: event)
        }
        guard let frame = bubbleState?.frame, frame.contains(point) else {
            return nil
        }
        return super.hitTest(point, with: event)
    }
}

// MARK: - Bubble

/// Holds the bubble's on-screen frame so the window knows which region is interactive.
/// A plain reference type — never triggers a re-render.
@MainActor
final class BubbleState {
    var frame: CGRect = .zero
}

private struct BubbleFrameKey: PreferenceKey {
    static var defaultValue: CGRect = .zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) { value = nextValue() }
}

private struct WireTapBubbleRootView: View {
    let systemImage: String
    let state: BubbleState
    let inspector: () -> AnyView

    @State private var committedOffset: CGSize = .zero
    @State private var dragOffset: CGSize = .zero
    @State private var showInspector = false

    var body: some View {
        GeometryReader { geo in
            bubble
                .background(
                    GeometryReader { proxy in
                        Color.clear.preference(key: BubbleFrameKey.self, value: proxy.frame(in: .global))
                    }
                )
                .position(x: geo.size.width - 40, y: geo.size.height - 140)
                .offset(x: committedOffset.width + dragOffset.width,
                        y: committedOffset.height + dragOffset.height)
                .gesture(
                    DragGesture(minimumDistance: 10)
                        .onChanged { dragOffset = $0.translation }
                        .onEnded {
                            committedOffset.width += $0.translation.width
                            committedOffset.height += $0.translation.height
                            dragOffset = .zero
                        }
                )
        }
        .ignoresSafeArea()
        .onPreferenceChange(BubbleFrameKey.self) { rect in
            state.frame = rect.insetBy(dx: -12, dy: -12)
        }
        .sheet(isPresented: $showInspector) {
            NavigationStack {
                inspector()
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button { showInspector = false } label: { Image(systemName: "xmark") }
                        }
                    }
            }
        }
    }

    private var bubble: some View {
        Image(systemName: systemImage)
            .font(.system(size: 20, weight: .bold))
            .foregroundColor(.white)
            .frame(width: 48, height: 48)
            .background(Circle().fill(Color.black.opacity(0.6)))
            .overlay(Circle().stroke(Color.white.opacity(0.35), lineWidth: 1))
            .shadow(radius: 4)
            .contentShape(Circle())
            .onTapGesture { showInspector = true }
    }
}

#endif
