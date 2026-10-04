import Observation
import SwiftUI

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

    private(set) var phase: Phase = .signedOut {
        didSet {
            updateAppLock()
            switch (oldValue, phase) {
            case (.signedIn, .signedIn):
                break
            case (_, .signedIn):
                Task { await loadAccountPhotos() }
            default:
                accountPhotos = [:]
            }
        }
    }
    var signInError: String?
    var verificationError: String?
    /// True while a SendCode/Validate request is in flight.
    private(set) var isVerifying = false
    /// Where the current code was sent, once one has been requested.
    private(set) var codeSentVia: MyChartWebService.CodeDelivery?

    /// Held only until verification succeeds, then moved to the Keychain.
    @ObservationIgnored private var pendingCredentials: (username: String, password: String)?

    /// When true, sign-in talks to the real RCH portal (unsanctioned web API).
    /// When false, the app runs on local mock data. Fixed by where the app
    /// runs: the Simulator is the only way into demo mode, so a real iPhone
    /// always uses the portal.
    let useLivePortal = Session.runsOnDevice

    private static var runsOnDevice: Bool {
        #if targetEnvironment(simulator)
        false
        #else
        true
        #endif
    }

    @ObservationIgnored private let mockService: PortalService = MockPortalService()
    @ObservationIgnored private lazy var liveService = MyChartWebService()

    /// Five-minute response cache shared by both backends (cleared whenever
    /// the backend changes, so they never mix).
    @ObservationIgnored private let cache = ResponseCache()
    @ObservationIgnored private lazy var cachedMock = CachedPortalService(base: mockService, cache: cache)
    @ObservationIgnored private lazy var cachedLive = CachedPortalService(base: liveService, cache: cache)

    private static let accountKey = "activeAccountID"

    /// Settings → "Save data on this iPhone": keeps the portal's responses on
    /// the device for five minutes so reopening the app is quicker. Off by
    /// default; turning it off deletes anything saved.
    var cachesDataOnDevice: Bool {
        didSet {
            UserDefaults.standard.set(cachesDataOnDevice, forKey: PortalDiskCache.enabledKey)
            if !cachesDataOnDevice { PortalDiskCache.shared.removeAll() }
        }
    }

    /// Signing in again with saved details at launch. The app shows its
    /// loading screen meanwhile, rather than flashing the login form.
    private(set) var isRestoring: Bool {
        didSet { updateAppLock() }
    }

    init() {
        cachesDataOnDevice = UserDefaults.standard.bool(forKey: PortalDiskCache.enabledKey)
        isRestoring = Self.runsOnDevice && Keychain.loadCredentials() != nil
        updateAppLock()
    }

    /// The Face ID lock only applies with an account to protect: signed in,
    /// or signing in again with saved details. Never at the login screen.
    private func updateAppLock() {
        if case .signedIn = phase {
            AppLock.shared.hasAccount = true
        } else {
            AppLock.shared.hasAccount = isRestoring
        }
    }

    /// Signs in again from the Keychain so the app opens straight into the
    /// dashboard. The portal has no long-lived session cookie we can reuse, so
    /// this replays the saved credentials; the remembered device ID normally
    /// means no verification code is needed. The portal sometimes turns a
    /// good sign-in away, so it's retried twice before giving up. The
    /// loading screen stays up meanwhile.
    func restoreSession() async {
        defer { isRestoring = false }
        guard useLivePortal, case .signedOut = phase,
              let credentials = Keychain.loadCredentials() else { return }
        for attempt in 0...2 {
            if attempt > 0 { try? await Task.sleep(for: .seconds(1)) }
            await signIn(username: credentials.username, password: credentials.password)
            // Signed in, or waiting for a verification code.
            guard case .signedOut = phase else { break }
        }
        // A stale password shouldn't leave an error on a screen the user
        // didn't ask for — just show the login form.
        if case .signedOut = phase { signInError = nil }
    }

    /// The backend for the current mode, behind the response cache.
    var service: PortalService {
        useLivePortal ? cachedLive : cachedMock
    }

    /// Pull to refresh: drop cached responses, in memory and on the device,
    /// so the next reads are fresh.
    func refreshData() async {
        PortalDiskCache.shared.removeAll()
        await cache.removeAll()
    }

    private func clearCache() {
        PortalDiskCache.shared.removeAll()
        Task { await cache.removeAll() }
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
        return Theme.accountTint(profile.linkedAccounts[idx], at: idx)
    }

    /// Saves a linked account's nickname, colour and photo change on the
    /// portal, then shows the portal's copy of that account.
    func customiseAccount(_ accountID: String, nickname: String, colour: Int,
                          photo: AccountPhotoChange) async throws {
        let accounts = try await service.customiseAccount(accountID, nickname: nickname, colour: colour, photo: photo)
        guard case var .signedIn(profile) = phase,
              let updated = accounts.first(where: { $0.id == accountID }),
              let index = profile.linkedAccounts.firstIndex(where: { $0.id == accountID }) else { return }
        var account = profile.linkedAccounts[index]
        account.name = updated.name
        account.initials = updated.initials
        account.tabColor = updated.tabColor ?? colour
        account.photoPath = updated.photoPath
        profile.linkedAccounts[index] = account
        phase = .signedIn(profile)
        switch photo {
        case .keep: break
        case let .replace(jpeg): accountPhotos[accountID] = UIImage(data: jpeg)
        case .remove: accountPhotos[accountID] = nil
        }
    }

    /// Account photos from the portal, by account ID. Held in memory only.
    private(set) var accountPhotos: [String: UIImage] = [:]

    private func loadAccountPhotos() async {
        for (id, data) in await service.accountPhotos() {
            if let image = UIImage(data: data) { accountPhotos[id] = image }
        }
    }

    var isAuthenticating: Bool {
        if case .authenticating = phase { return true }
        return false
    }

    func signIn(username: String, password: String) async {
        signInError = nil
        phase = .authenticating
        await cache.removeAll()
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
        // Don't leave health data in memory after signing out, or on the
        // Home Screen.
        clearCache()
        WidgetPublisher.shared.clear()
        phase = .signedOut
    }
}
