import SwiftUI

/// The signed-in shell, like the Health app: Home (the dashboard) and
/// Browse (every section), each in its own navigation stack.
struct MainTabView: View {
    let profile: PatientProfile

    @Environment(Session.self) private var session

    var body: some View {
        TabView {
            Tab("Home", systemImage: "house.fill") {
                NavigationStack { DashboardView(profile: profile) }
            }
            Tab("Browse", systemImage: "square.grid.2x2.fill") {
                NavigationStack { BrowseView() }.id(session.patientID)
            }
        }
        .tint(Theme.brand)
    }
}

#Preview {
    MainTabView(profile: PatientProfile(
        id: "p", fullName: "Sallie Anderson", preferredName: "Sallie", initials: "S",
        linkedAccounts: [
            LinkedAccount(id: "acct-sallie", name: "Sallie", initials: "S", unreadCount: 1),
            LinkedAccount(id: "acct-sal", name: "Sal", initials: "S", unreadCount: 0)
        ]))
    .environment(Session())
}
