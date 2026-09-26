import SwiftUI
import Observation

/// Owns authentication state and the active service for the whole app.
/// Injected into the environment by `MyApp`.
@MainActor
@Observable
final class Session {
    enum Phase {
        case signedOut
        case authenticating
        /// Password accepted; the portal wants a one-time code.
        case verifyingCode
        case signedIn(PatientProfile)
    }

    private(set) var phase: Phase = .signedOut
    var signInError: String?
    var verificationError: String?
    /// True while a SendCode/Validate request is in flight.
    private(set) var isVerifying = false
    /// Where the current code was sent, once one has been requested.
    private(set) var codeSentVia: MyChartWebService.CodeDelivery?

    /// Held only until verification succeeds, then moved to the Keychain.
    @ObservationIgnored private var pendingCredentials: (username: String, password: String)?

    /// When true, sign-in talks to the real RCH portal (unsanctioned web API).
    /// When false, the app runs on local mock data.
    var useLivePortal: Bool {
        didSet { UserDefaults.standard.set(useLivePortal, forKey: Self.liveKey) }
    }

    @ObservationIgnored private let mockService: PortalService = MockPortalService()
    @ObservationIgnored private lazy var liveService = MyChartWebService()

    private static let liveKey = "useLivePortal"
    private static let accountKey = "activeAccountID"

    init() {
        useLivePortal = UserDefaults.standard.bool(forKey: Self.liveKey)
    }

    /// Signs in again from the Keychain so the app opens straight into the
    /// dashboard. The portal has no long-lived session cookie we can reuse, so
    /// this replays the saved credentials; the remembered device ID normally
    /// means no verification code is needed.
    func restoreSession() async {
        guard useLivePortal, case .signedOut = phase,
              let credentials = Keychain.loadCredentials() else { return }
        await signIn(username: credentials.username, password: credentials.password)
        // A stale password shouldn't leave an error on a screen the user
        // didn't ask for — just show the login form.
        if case .signedOut = phase { signInError = nil }
    }

    /// The backend for the current mode.
    var service: PortalService {
        useLivePortal ? liveService : mockService
    }

    /// The linked account whose record is currently being viewed. Persisted so
    /// the app reopens on the same child rather than resetting to the
    /// account-holder (whose own chart is usually empty).
    var activeAccountID: String = "" {
        didSet { UserDefaults.standard.set(activeAccountID, forKey: Self.accountKey) }
    }

    var profile: PatientProfile? {
        if case let .signedIn(profile) = phase { return profile }
        return nil
    }

    /// Whose record the screens should load — the account chosen in the
    /// switcher, falling back to the signed-in user.
    var patientID: String {
        activeAccountID.isEmpty ? (profile?.id ?? "") : activeAccountID
    }

    var activeAccount: LinkedAccount? {
        guard let profile else { return nil }
        return profile.linkedAccounts.first { $0.id == activeAccountID } ?? profile.linkedAccounts.first
    }

    /// Colour tied to the active account, shared by the avatar and switcher.
    var activeTint: Color {
        guard let profile,
              let idx = profile.linkedAccounts.firstIndex(where: { $0.id == activeAccountID })
        else { return Theme.brand }
        return Theme.leaves[idx % Theme.leaves.count]
    }

    var isAuthenticating: Bool {
        if case .authenticating = phase { return true }
        return false
    }

    func signIn(username: String, password: String) async {
        signInError = nil
        phase = .authenticating
        do {
            let profile = try await service.signIn(username: username, password: password)
            if useLivePortal {
                Keychain.save(username: username, password: password)
            }
            adoptAccount(for: profile)
            phase = .signedIn(profile)
        } catch MyChartError.twoFactorRequired {
            pendingCredentials = (username, password)
            verificationError = nil
            codeSentVia = nil
            phase = .verifyingCode
        } catch {
            signInError = Self.message(for: error)
            phase = .signedOut
        }
    }

    // MARK: - Two-factor

    func sendVerificationCode(via delivery: MyChartWebService.CodeDelivery) async {
        let resend = codeSentVia == delivery
        await runVerificationStep {
            try await self.liveService.sendVerificationCode(via: delivery, resend: resend)
            self.codeSentVia = delivery
        }
    }

    func verifyCode(_ code: String, rememberDevice: Bool) async {
        await runVerificationStep {
            let profile = try await self.liveService.verifyCode(code, rememberDevice: rememberDevice)
            if let credentials = self.pendingCredentials {
                Keychain.save(username: credentials.username, password: credentials.password)
            }
            self.pendingCredentials = nil
            self.adoptAccount(for: profile)
            self.phase = .signedIn(profile)
        }
    }

    /// Restores the previously viewed account if it's still linked, otherwise
    /// falls back to the first one.
    private func adoptAccount(for profile: PatientProfile) {
        let remembered = UserDefaults.standard.string(forKey: Self.accountKey)
        if let remembered, profile.linkedAccounts.contains(where: { $0.id == remembered }) {
            activeAccountID = remembered
        } else {
            activeAccountID = profile.linkedAccounts.first?.id ?? profile.id
        }
    }

    /// Abandons the half-finished sign-in and returns to the login screen.
    func cancelVerification() {
        pendingCredentials = nil
        codeSentVia = nil
        verificationError = nil
        phase = .signedOut
    }

    private func runVerificationStep(_ step: () async throws -> Void) async {
        verificationError = nil
        isVerifying = true
        defer { isVerifying = false }
        do {
            try await step()
        } catch {
            verificationError = Self.message(for: error)
        }
    }

    private static func message(for error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }

    func signOut() {
        Keychain.clear()
        phase = .signedOut
    }
}
