import SwiftUI

/// Switches between the sign-in screen and the authenticated app.
struct RootView: View {
    @Environment(Session.self) private var session

    var body: some View {
        switch session.phase {
        case .signedOut, .authenticating:
            LoginView()
        case let .signedIn(profile):
            MainTabView(profile: profile)
        }
    }
}

#Preview {
    RootView()
        .environment(Session())
}
