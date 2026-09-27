import SwiftUI

/// App settings. Also the home for account / persona switching, which used to
/// live on the dashboard.
struct SettingsView: View {
    let profile: PatientProfile
    @Environment(Session.self) private var session
    @Environment(\.dismiss) private var dismiss

    @State private var notificationsEnabled = true
    @State private var faceIDEnabled = true
    /// Explore More cards closed on Home (shared with the dashboard).
    @AppStorage("dismissedExploreItems") private var dismissedExplore = ""

    var body: some View {
        List {
            profileSection
            accountsSection
            preferencesSection
            dataSection
            supportSection
            signOutSection
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Profile

    private var profileSection: some View {
        Section {
            HStack(spacing: 16) {
                AvatarView(initials: session.activeAccount?.initials ?? profile.initials,
                           tint: session.activeTint, size: 56)
                VStack(alignment: .leading, spacing: 2) {
                    Text(session.activeAccount?.name ?? profile.fullName)
                        .font(.title3.bold())
                    Text("Patient & Family Portal")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 6)
        }
    }

    // MARK: - Accounts

    private var accountsSection: some View {
        Section {
            ForEach(Array(profile.linkedAccounts.enumerated()), id: \.element.id) { index, account in
                Button {
                    session.activeAccountID = account.id
                } label: {
                    HStack(spacing: 14) {
                        AvatarView(initials: account.initials,
                                   tint: Theme.leaves[index % Theme.leaves.count],
                                   size: 34)
                        Text(account.name).foregroundStyle(.primary)
                        Spacer()
                        if account.id == session.activeAccountID {
                            Image(systemName: "checkmark")
                                .foregroundStyle(Theme.brand)
                                .fontWeight(.semibold)
                        }
                    }
                }
            }
            Button {
            } label: {
                Label("Manage linked accounts", systemImage: "person.2.badge.gearshape")
            }
        } header: {
            Text("Accounts")
        } footer: {
            Text("Switch between the people whose records you manage.")
        }
    }

    // MARK: - Preferences

    private var preferencesSection: some View {
        Section("Preferences") {
            Toggle(isOn: $notificationsEnabled) {
                Label("Notifications", systemImage: "bell.badge")
            }
            Toggle(isOn: $faceIDEnabled) {
                Label("Unlock with Face ID", systemImage: "faceid")
            }
            Button {
                dismissedExplore = ""
            } label: {
                Label("Show Hidden Explore Cards", systemImage: "rectangle.stack.badge.plus")
            }
            .disabled(dismissedExplore.isEmpty)
            NavigationLink {
                ContentUnavailableView("Appearance", systemImage: "paintbrush",
                                       description: Text("Theme options would go here."))
            } label: {
                Label("Appearance", systemImage: "paintbrush")
            }
        }
    }

    // MARK: - Data & privacy

    private var dataSection: some View {
        @Bindable var session = session
        return Section {
            Toggle(isOn: $session.cachesDataOnDevice) {
                Label("Save Data on This iPhone", systemImage: "internaldrive")
            }
        } header: {
            Text("Data & Privacy")
        } footer: {
            Text("Keeps a copy of your portal data on this iPhone for up to 5 minutes, so reopening the app is quicker. It's encrypted while your iPhone is locked, and deleted when you sign out, pull to refresh or turn this off. Applies to the live portal only.")
        }
    }

    // MARK: - Support

    private var supportSection: some View {
        Section("Support") {
            Link(destination: URL(string: "https://www.rch.org.au")!) {
                Label("Help & FAQs", systemImage: "questionmark.circle")
            }
            Link(destination: URL(string: "https://www.rch.org.au")!) {
                Label("Contact the hospital", systemImage: "phone")
            }
            LabeledContent {
                Text("1.0.0")
            } label: {
                Label("Version", systemImage: "info.circle")
            }
        }
    }

    // MARK: - Sign out

    private var signOutSection: some View {
        Section {
            Button(role: .destructive) {
                session.signOut()
            } label: {
                Label("Sign out", systemImage: "rectangle.portrait.and.arrow.right")
                    .frame(maxWidth: .infinity)
            }
        }
    }
}

#Preview {
    NavigationStack {
        SettingsView(profile: PatientProfile(
            id: "p", fullName: "Sallie Anderson", preferredName: "Sallie", initials: "S",
            linkedAccounts: [
                LinkedAccount(id: "acct-sallie", name: "Sallie", initials: "S", unreadCount: 1),
                LinkedAccount(id: "acct-sal", name: "Sal", initials: "S", unreadCount: 0)
            ]))
    }
    .environment(Session())
}
