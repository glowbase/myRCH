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
/// between children. Detailed settings live on their own pages (see
/// AppSettingsViews.swift) so this one stays short.
struct SettingsView: View {
    let profile: PatientProfile
    @Environment(Session.self) private var session

    /// Explore More cards closed on Home (shared with the dashboard).
    @AppStorage("dismissedExploreItems") private var dismissedExplore = ""
    @AppStorage(AppAppearance.storageKey) private var appearance = AppAppearance.system.rawValue
    @State private var appLock = AppLock.shared
    /// From the portal's record header, for the profile row.
    @State private var urNumber: String?
    @State private var showsEditHome = false
    @State private var confirmsSignOut = false

    var body: some View {
        List {
            profileHeader
            recordsSection
            healthSection
            portalAccountSection
            appSection
            privacySection
            aboutSection
            signOutSection
        }
        .navigationTitle("Profile")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showsEditHome) { EditHomeSheet() }
    }

    // MARK: - Profile

    /// Like the top of iOS Settings: avatar on the left, then the child's
    /// name, age and UR number.
    private var profileHeader: some View {
        Section {
            HStack(spacing: 14) {
                AvatarView(initials: session.activeAccount?.initials ?? profile.initials,
                           tint: session.activeTint, size: 64,
                           image: session.activeAccount.flatMap { session.accountPhotos[$0.id] })
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(session.activeAccount?.name ?? profile.fullName)
                            .font(.title2.weight(.semibold))
                            .lineLimit(2)
                        // So sample records are never mistaken for real ones.
                        if !session.useLivePortal {
                            Pill(text: "Demo", tint: .orange)
                                .fixedSize()
                        }
                    }
                    if let birth = session.activeAccount?.dateOfBirth {
                        Text("\(birth.ageDescription) · Born \(birth.formatted(date: .abbreviated, time: .omitted))")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    if let urNumber {
                        Text("UR \(urNumber)")
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
            }
            .accessibilityElement(children: .combine)
        }
        .task(id: session.patientID) {
            // Never show one child's UR number under another's name.
            urNumber = nil
            urNumber = try? await session.service.recordHeader(for: session.patientID).urNumber
        }
    }

    // MARK: - Records

    @ViewBuilder
    private var recordsSection: some View {
        if profile.linkedAccounts.count > 1 {
            Section {
                ForEach(Array(profile.linkedAccounts.enumerated()), id: \.element.id) { index, account in
                    Button {
                        session.activeAccountID = account.id
                    } label: {
                        HStack(spacing: 14) {
                            AccountAvatar(account: account, index: index, size: 34)
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
                NavigationLink {
                    EditAccountsView()
                } label: {
                    SettingsRow("Nicknames and Photos", symbol: "person.crop.circle.badge.plus", color: Theme.proxy)
                }
            } header: {
                Text("Records")
            } footer: {
                Text("Switch between the children whose records you manage.")
            }
        }
    }

    // MARK: - Health

    /// For the selected child.
    private var healthSection: some View {
        Section("Health") {
            NavigationLink {
                MedicalIDView(patientID: session.patientID)
            } label: {
                SettingsRow("Medical ID", symbol: "staroflife.fill", color: .red)
            }
            NavigationLink {
                SharedRemindersView()
            } label: {
                SettingsRow("Share Medication Reminders", symbol: "person.2.fill", color: Theme.medication)
            }
        }
    }

    // MARK: - Portal account

    /// The signed-in adult's own details, whichever child is selected.
    private var portalAccountSection: some View {
        Section("Portal Account") {
            NavigationLink {
                PersonalInformationView()
            } label: {
                SettingsRow("Personal Information", symbol: "person.text.rectangle.fill", color: .teal)
            }
            NavigationLink {
                SecuritySettingsView()
            } label: {
                SettingsRow("Login & Security", symbol: "lock.shield.fill", color: .gray)
            }
            NavigationLink {
                CommunicationPreferencesView()
            } label: {
                SettingsRow("Communication Preferences", symbol: "message.badge.fill", color: .blue)
            }
        }
    }

    // MARK: - App

    private var appSection: some View {
        Section("App") {
            Picker(selection: $appearance) {
                ForEach(AppAppearance.allCases) { Text($0.title).tag($0.rawValue) }
            } label: {
                SettingsRow("Appearance", symbol: "circle.lefthalf.filled", color: .indigo)
            }
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
            NavigationLink {
                NotificationSettingsView()
            } label: {
                SettingsRow("Notifications", symbol: "bell.badge.fill", color: .red)
            }
            NavigationLink {
                LockScreenSettingsView()
            } label: {
                SettingsRow("Lock Screen & Widgets", symbol: "platter.filled.bottom.iphone", color: .blue)
            }
            NavigationLink {
                SiriSettingsView()
            } label: {
                SettingsRow("Siri & Shortcuts", symbol: "mic.fill", color: .purple)
            }
        }
    }

    // MARK: - Privacy

    @ViewBuilder
    private var privacySection: some View {
        @Bindable var session = session
        Section {
            Toggle(isOn: Binding(get: { appLock.isEnabled },
                                 set: { enabled in Task { await appLock.setEnabled(enabled) } })) {
                SettingsRow("Require \(appLock.method)", symbol: appLock.symbol, color: .green)
            }
            .disabled(!appLock.isAvailable)
        } header: {
            Text("Privacy")
        } footer: {
            Text(appLock.isAvailable
                 ? "Asks for \(appLock.method) each time you open myRCH, and hides your records in the app switcher. Your iPhone passcode works too."
                 : "Set a passcode for your iPhone in Settings to lock myRCH.")
        }
        Section {
            Toggle(isOn: $session.cachesDataOnDevice) {
                SettingsRow("Save Data on This iPhone", symbol: "internaldrive.fill", color: .gray)
            }
        } footer: {
            Text("Keeps a copy of your portal data on this iPhone for up to 5 minutes, so reopening the app is quicker. It's encrypted while your iPhone is locked, and deleted when you sign out, pull to refresh or turn this off.")
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
                PrivacyView()
            } label: {
                SettingsRow("Privacy", symbol: "hand.raised.fill", color: .blue)
            }
            NavigationLink {
                LicencesView()
            } label: {
                SettingsRow("Licences", symbol: "doc.text.fill", color: .gray)
            }
            NavigationLink {
                ChangelogView()
            } label: {
                LabeledContent {
                    Text(version)
                } label: {
                    SettingsRow("Version", symbol: "info.circle.fill", color: .gray)
                }
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
    .environment(MedicationStore.shared)
}
