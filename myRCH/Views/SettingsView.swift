import SwiftUI

/// Chosen in Settings; applied at the app's root.
enum AppAppearance: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    static let storageKey = "appearance"

    var title: String {
        switch self {
        case .system: "Automatic"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

/// Profile and settings, laid out like the Health app's profile: the person
/// at the top, then grouped rows with coloured icons. Also where you switch
/// between children.
struct SettingsView: View {
    let profile: PatientProfile
    @Environment(Session.self) private var session
    @Environment(\.openURL) private var openURL

    /// Explore More cards closed on Home (shared with the dashboard).
    @AppStorage("dismissedExploreItems") private var dismissedExplore = ""
    @AppStorage(AppAppearance.storageKey) private var appearance = AppAppearance.system.rawValue
    /// The Allergy Alert widget shows allergies without unlocking, so it's opt-in.
    @AppStorage(WidgetPublisher.showsAllergiesKey) private var showsAllergiesOnLockScreen = false
    @AppStorage(ActivityManager.enabledKey) private var liveActivitiesEnabled = true
    @State private var showsEditHome = false
    @State private var confirmsSignOut = false

    var body: some View {
        List {
            profileHeader
            healthSection
            accountsSection
            homeSection
            preferencesSection
            dataSection
            aboutSection
            signOutSection
        }
        .navigationTitle("Profile")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showsEditHome) { EditHomeSheet() }
    }

    // MARK: - Profile

    /// Like the top of iOS Settings: avatar on the left, name beside it, in
    /// a row about two and a half normal rows tall.
    private var profileHeader: some View {
        Section {
            HStack(spacing: 16) {
                AvatarView(initials: session.activeAccount?.initials ?? profile.initials,
                           tint: session.activeTint, size: 72)
                VStack(alignment: .leading, spacing: 3) {
                    Text(session.activeAccount?.name ?? profile.fullName)
                        .font(.title2.weight(.semibold))
                        .lineLimit(2)
                    Text(session.useLivePortal ? "My RCH Portal" : "Demo mode")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .frame(minHeight: 96)
            .padding(.vertical, 6)
            .accessibilityElement(children: .combine)
        }
    }

    private var healthSection: some View {
        Section {
            NavigationLink {
                MedicalIDView(patientID: session.patientID)
            } label: {
                SettingsRow("Medical ID", symbol: "staroflife.fill", color: .red)
            }
            NavigationLink {
                HealthSummaryView(patientID: session.patientID)
            } label: {
                SettingsRow("Health Summary", symbol: "heart.text.clipboard.fill", color: .pink)
            }
            NavigationLink {
                SharedRemindersView()
            } label: {
                SettingsRow("Share Medication Reminders", symbol: "person.2.fill", color: Theme.medication)
            }
        }
    }

    // MARK: - Accounts

    @ViewBuilder
    private var accountsSection: some View {
        if profile.linkedAccounts.count > 1 {
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
            } header: {
                Text("Records")
            } footer: {
                Text("Switch between the children whose records you manage.")
            }
        }
    }

    // MARK: - Home

    private var homeSection: some View {
        Section("Home") {
            Button {
                showsEditHome = true
            } label: {
                SettingsRow("Edit Home", symbol: "square.grid.2x2.fill", color: Theme.brand)
            }
            .foregroundStyle(.primary)
            Button {
                dismissedExplore = ""
            } label: {
                SettingsRow("Show Hidden Explore Cards", symbol: "rectangle.stack.fill", color: .yellow)
            }
            .foregroundStyle(.primary)
            .disabled(dismissedExplore.isEmpty)
        }
    }

    // MARK: - Preferences

    @ViewBuilder
    private var preferencesSection: some View {
        Section {
            Picker(selection: $appearance) {
                ForEach(AppAppearance.allCases) { Text($0.title).tag($0.rawValue) }
            } label: {
                SettingsRow("Appearance", symbol: "circle.lefthalf.filled", color: .indigo)
            }
            Button {
                if let url = URL(string: UIApplication.openNotificationSettingsURLString) { openURL(url) }
            } label: {
                SettingsRow("Notifications", symbol: "bell.badge.fill", color: .red, showsChevron: true)
            }
            .foregroundStyle(.primary)
        } header: {
            Text("Preferences")
        } footer: {
            Text("Medication reminders use iOS notifications. Turn them on or off, or change how they appear, in Settings.")
        }
        Section {
            Toggle(isOn: $liveActivitiesEnabled) {
                SettingsRow("Live Activities", symbol: "platter.filled.bottom.iphone", color: Theme.medication)
            }
            .onChange(of: liveActivitiesEnabled) { WidgetPublisher.shared.settingsChanged() }
        } footer: {
            Text("Shows a dose that's due, with Taken and Skip, and the day of a visit, on the Lock Screen and in the Dynamic Island. They start when you open myRCH.")
        }
        Section {
            Toggle(isOn: $showsAllergiesOnLockScreen) {
                SettingsRow("Allergies on Lock Screen", symbol: "allergens.fill", color: .orange)
            }
            .onChange(of: showsAllergiesOnLockScreen) { WidgetPublisher.shared.settingsChanged() }
        } header: {
            Text("Widgets")
        } footer: {
            Text("Lets the Allergy Alert widget show allergies without unlocking your iPhone, like Medical ID, so a first responder can see them. Anyone who picks up your phone can too.")
        }
    }

    // MARK: - Data & privacy

    private var dataSection: some View {
        @Bindable var session = session
        return Section {
            Toggle(isOn: $session.cachesDataOnDevice) {
                SettingsRow("Save Data on This iPhone", symbol: "internaldrive.fill", color: .gray)
            }
        } header: {
            Text("Data & Privacy")
        } footer: {
            Text("Keeps a copy of your portal data on this iPhone for up to 5 minutes, so reopening the app is quicker. It's encrypted while your iPhone is locked, and deleted when you sign out, pull to refresh or turn this off. Applies to the live portal only.")
        }
    }

    // MARK: - About

    private var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = info?["CFBundleVersion"] as? String ?? "1"
        return "\(short) (\(build))"
    }

    private var aboutSection: some View {
        Section {
            if let site = URL(string: "https://www.rch.org.au") {
                Link(destination: site) {
                    SettingsRow("RCH Website", symbol: "safari.fill", color: .blue, showsChevron: true)
                }
                .foregroundStyle(.primary)
            }
            // The hospital's main switchboard.
            if let phone = URL(string: "tel:+61393455522") {
                Link(destination: phone) {
                    SettingsRow("Call the Hospital", symbol: "phone.fill", color: .green, showsChevron: true)
                }
                .foregroundStyle(.primary)
            }
            NavigationLink {
                LicencesView()
            } label: {
                SettingsRow("Licences", symbol: "doc.text.fill", color: .gray)
            }
            LabeledContent {
                Text(version).foregroundStyle(.secondary)
            } label: {
                SettingsRow("Version", symbol: "info.circle.fill", color: .gray)
            }
        } header: {
            Text("About")
        } footer: {
            Text("myRCH is an independent app. It isn't made, endorsed or supported by The Royal Children's Hospital. In an emergency, call 000.")
        }
    }

    // MARK: - Sign out

    private var signOutSection: some View {
        Section {
            Button("Sign Out", role: .destructive) {
                confirmsSignOut = true
            }
            .frame(maxWidth: .infinity)
            .confirmationDialog("Sign out of myRCH?", isPresented: $confirmsSignOut, titleVisibility: .visible) {
                Button("Sign Out", role: .destructive) { session.signOut() }
            } message: {
                Text("Saved data and widgets on this iPhone are removed. Medication notes and reminders stay.")
            }
        }
    }
}

/// An iOS Settings-style row: a white symbol on a small coloured rounded
/// square, then the title.
struct SettingsRow: View {
    let title: String
    let symbol: String
    let color: Color
    var showsChevron = false

    init(_ title: String, symbol: String, color: Color, showsChevron: Bool = false) {
        self.title = title
        self.symbol = symbol
        self.color = color
        self.showsChevron = showsChevron
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(color.gradient, in: .rect(cornerRadius: 7))
            Text(title)
            if showsChevron {
                Spacer()
                Image(systemName: "arrow.up.forward")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
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
