import SwiftUI

/// Switches between the sign-in screen and the authenticated app.
struct RootView: View {
    @Environment(Session.self) private var session
    @Environment(MedicationStore.self) private var store

    var body: some View {
        @Bindable var store = store
        switch session.phase {
        case .signedOut, .authenticating:
            LoginView()
        case .verifyingCode:
            VerificationCodeView()
        case let .signedIn(profile):
            MainTabView(profile: profile)
                // A tapped medication reminder opens its logging sheet, on
                // top of whatever screen is showing.
                .sheet(item: $store.openSlot) { DoseLogSheet(slot: $0) }
        }
    }
}

#Preview {
    RootView()
        .environment(Session())
        .environment(MedicationStore())
}
