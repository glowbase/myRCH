import SwiftUI

/// The signed-in shell: a tab bar giving direct access to the main sections,
/// each in its own navigation stack. Home is the dashboard.
struct MainTabView: View {
    let profile: PatientProfile

    @Environment(Session.self) private var session

    var body: some View {
        TabView {
            Tab("Home", systemImage: "house.fill") {
                NavigationStack { DashboardView(profile: profile) }
            }
            Tab("Visits", systemImage: "calendar") {
                NavigationStack { AppointmentsView(patientID: session.patientID) }.id(session.patientID)
            }
            Tab("Results", systemImage: "testtube.2") {
                NavigationStack { TestResultsView(patientID: session.patientID) }.id(session.patientID)
            }
            Tab("Messages", systemImage: "envelope.fill") {
                NavigationStack { MessagesView(patientID: session.patientID) }.id(session.patientID)
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
