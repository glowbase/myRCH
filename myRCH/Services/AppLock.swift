import LocalAuthentication
import Observation
import SwiftUI
import UIKit

/// Optional Face ID (or passcode) lock. The app locks each time it goes to
/// the background and asks to unlock when it comes back. While it isn't
/// active, a cover hides the records from the app switcher.
///
/// The lock screen lives in its own window above the app's, so it also
/// covers any sheet that's open (e.g. a dose being logged).
@MainActor @Observable
final class AppLock {
    static let shared = AppLock()
    static let enabledKey = "appLockEnabled"

    var isEnabled: Bool = UserDefaults.standard.bool(forKey: AppLock.enabledKey) {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: Self.enabledKey)
            if !isEnabled { isLocked = false }
        }
    }

    /// Needs Face ID, Touch ID or the passcode to open.
    private(set) var isLocked: Bool
    /// The app isn't in front (app switcher, Control Centre, a Face ID prompt).
    private(set) var isInactive = false
    private(set) var isAuthenticating = false

    private var window: UIWindow?

    private init() {
        isLocked = UserDefaults.standard.bool(forKey: AppLock.enabledKey)
    }

    /// Face ID, Touch ID, Optic ID or just the passcode, for labels.
    var method: String {
        let context = LAContext()
        _ = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        switch context.biometryType {
        case .faceID: return "Face ID"
        case .touchID: return "Touch ID"
        case .opticID: return "Optic ID"
        default: return "Passcode"
        }
    }

    var symbol: String {
        switch method {
        case "Face ID": "faceid"
        case "Touch ID": "touchid"
        case "Optic ID": "opticid"
        default: "lock.fill"
        }
    }

    /// False when the iPhone has no passcode set, so there's nothing to unlock with.
    var isAvailable: Bool {
        LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: nil)
    }

    // MARK: Window

    /// Called once the scene connects; the cover is hidden until needed.
    func attach(to scene: UIWindowScene) {
        let window = UIWindow(windowScene: scene)
        window.windowLevel = .alert + 1
        let host = UIHostingController(rootView: AppLockScreen())
        host.view.backgroundColor = .clear
        window.rootViewController = host
        self.window = window
        updateWindow()
    }

    private func updateWindow() {
        window?.isHidden = !(isEnabled && (isLocked || isInactive))
    }

    // MARK: Lifecycle

    func scenePhaseChanged(_ phase: ScenePhase) {
        switch phase {
        case .background:
            if isEnabled { isLocked = true }
            isInactive = true
        case .inactive:
            isInactive = true
        case .active:
            isInactive = false
            // Not while a prompt is up: it makes the app inactive then
            // active again, which would ask twice.
            if isLocked && !isAuthenticating { Task { await unlock() } }
        @unknown default:
            break
        }
        updateWindow()
    }

    /// Turning the lock on proves the person can unlock first, so nobody is
    /// locked out by a setting they can't satisfy.
    func setEnabled(_ enabled: Bool) async {
        guard enabled else { isEnabled = false; updateWindow(); return }
        if await authenticate(reason: "Turn on \(method) for myRCH") {
            isEnabled = true
        }
        updateWindow()
    }

    func unlock() async {
        guard isLocked else { return }
        if await authenticate(reason: "Unlock your children's health records") {
            isLocked = false
        }
        updateWindow()
    }

    private func authenticate(reason: String) async -> Bool {
        guard !isAuthenticating else { return false }
        isAuthenticating = true
        defer { isAuthenticating = false }
        let context = LAContext()
        // Without a passcode there's no way in; don't trap anyone.
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: nil) else { return true }
        return (try? await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)) ?? false
    }
}

/// What the lock window shows: an unlock button while locked, otherwise a
/// plain cover for the app switcher.
private struct AppLockScreen: View {
    @State private var lock = AppLock.shared
    @AppStorage(AppAppearance.storageKey) private var appearance = AppAppearance.system.rawValue

    var body: some View {
        ZStack {
            Rectangle().fill(.background).ignoresSafeArea()
            VStack(spacing: 16) {
                Image(systemName: lock.isLocked ? "lock.fill" : "heart.text.clipboard.fill")
                    .font(.system(size: 44, weight: .semibold))
                    .foregroundStyle(Theme.brand)
                Text(lock.isLocked ? "myRCH is Locked" : "myRCH")
                    .font(.system(.title2, design: .rounded).bold())
                    .foregroundStyle(Theme.ink)
                if lock.isLocked && !lock.isInactive {
                    Button {
                        Task { await lock.unlock() }
                    } label: {
                        Label("Unlock with \(lock.method)", systemImage: lock.symbol)
                            .padding(.horizontal, 8)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.brand)
                    .padding(.top, 8)
                    .disabled(lock.isAuthenticating)
                }
            }
            .padding()
        }
        .preferredColorScheme(AppAppearance(rawValue: appearance)?.colorScheme)
    }
}
