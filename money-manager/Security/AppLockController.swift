import SwiftUI
import UIKit
import LocalAuthentication
import MoneyCore

/// Owns the app-lock state and the window that hides the app.
///
/// The lock UI lives in its own `UIWindow` above `.alert`, because a SwiftUI
/// overlay on the root view cannot cover sheets that are already presented.
@MainActor @Observable
final class AppLockController {
    let settings: AppLockSettings

    private(set) var isLocked: Bool {
        didSet { refreshWindow() }
    }
    private(set) var scenePhase: ScenePhase = .background {
        didSet { refreshWindow() }
    }

    @ObservationIgnored private var backgroundedAt: Date?
    @ObservationIgnored private var isAuthenticating = false
    /// Prompt automatically on the next `.active`; cleared once a prompt starts, so cancelling doesn't loop.
    @ObservationIgnored private var shouldAutoPrompt: Bool
    @ObservationIgnored private var window: UIWindow?
    @ObservationIgnored private var previousKeyWindow: UIWindow?

    init() {
        let settings = AppLockSettings()
        self.settings = settings
        // Cold start: locked whenever the lock is on.
        self.isLocked = settings.isEnabled
        self.shouldAutoPrompt = settings.isEnabled
    }

    /// Hide everything while the lock is on and the app isn't frontmost (app switcher snapshot).
    private var showsPrivacyCover: Bool { settings.isEnabled && scenePhase != .active }

    func handle(scenePhase newPhase: ScenePhase) {
        // The Face ID prompt itself makes the phase `.inactive`; only `.background` starts the clock.
        if newPhase == .background, backgroundedAt == nil {
            backgroundedAt = Date()
        }
        if newPhase == .active, let since = backgroundedAt {
            backgroundedAt = nil
            if AppLockPolicy.shouldLock(
                enabled: settings.isEnabled, backgroundedAt: since,
                now: Date(), graceSeconds: settings.graceSeconds
            ) {
                isLocked = true
                shouldAutoPrompt = true
            }
        }
        scenePhase = newPhase
        if newPhase == .active, isLocked, shouldAutoPrompt {
            Task { await unlock() }
        }
    }

    func unlock() async {
        guard isLocked else { return }
        shouldAutoPrompt = false
        if await authenticate() { isLocked = false }
    }

    /// Device-owner authentication (biometrics with passcode fallback). False when cancelled, failed or already prompting.
    func authenticate() async -> Bool {
        guard !isAuthenticating else { return false }
        isAuthenticating = true
        defer { isAuthenticating = false }
        let context = LAContext()
        do {
            return try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "Buka Duitku")
        } catch {
            return false
        }
    }

    // MARK: Window

    private func refreshWindow() {
        let needsWindow = isLocked || showsPrivacyCover
        if needsWindow {
            if window == nil { window = makeWindow() }
            guard let window else { return }
            if window.isHidden {
                previousKeyWindow = window.windowScene?.keyWindow
                window.isHidden = false
            }
            // Take focus so touches and VoiceOver can't reach sheets underneath.
            window.makeKey()
        } else if let window, !window.isHidden {
            window.isHidden = true
            previousKeyWindow?.makeKey()
            previousKeyWindow = nil
        }
    }

    private func makeWindow() -> UIWindow? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        guard let scene = scenes.first(where: { $0.activationState == .foregroundActive })
            ?? scenes.first(where: { $0.activationState == .foregroundInactive })
            ?? scenes.first
        else { return nil }
        let window = UIWindow(windowScene: scene)
        window.windowLevel = UIWindow.Level.alert + 1
        window.backgroundColor = .clear
        let host = UIHostingController(rootView: AppLockOverlay(controller: self))
        host.view.backgroundColor = .clear
        window.rootViewController = host
        return window
    }
}

/// Content of the lock window: the lock screen, or an opaque cover.
private struct AppLockOverlay: View {
    let controller: AppLockController

    var body: some View {
        if controller.isLocked {
            LockScreenView(controller: controller)
        } else {
            ZStack {
                Color(.systemBackground)
                Image(systemName: "lock.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(.secondary)
            }
            .ignoresSafeArea()
            .accessibilityHidden(true)
        }
    }
}
