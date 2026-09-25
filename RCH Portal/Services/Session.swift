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
        case signedIn(PatientProfile)
    }

    private(set) var phase: Phase = .signedOut
    var signInError: String?

    /// When true, sign-in talks to the real RCH portal (unsanctioned web API).
    /// When false, the app runs on local mock data.
    var useLivePortal: Bool {
        didSet { UserDefaults.standard.set(useLivePortal, forKey: Self.liveKey) }
    }

    @ObservationIgnored private let mockService: PortalService = MockPortalService()
    @ObservationIgnored private lazy var liveService: PortalService = MyChartWebService()

    private static let liveKey = "useLivePortal"

    init() {
        useLivePortal = UserDefaults.standard.bool(forKey: Self.liveKey)
    }

    /// The backend for the current mode.
    var service: PortalService {
        useLivePortal ? liveService : mockService
    }

    /// The linked account whose record is currently being viewed.
    var activeAccountID: String = ""

    var profile: PatientProfile? {
        if case let .signedIn(profile) = phase { return profile }
        return nil
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
            activeAccountID = profile.linkedAccounts.first?.id ?? profile.id
            phase = .signedIn(profile)
        } catch {
            signInError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            phase = .signedOut
        }
    }

    func signOut() {
        Keychain.clear()
        phase = .signedOut
    }
}
