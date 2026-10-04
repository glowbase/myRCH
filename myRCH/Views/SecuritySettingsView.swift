import SwiftUI

/// The account holder's login, two-step verification and device settings,
/// as held by the portal. Preview features and remembered devices can be
/// switched here, and passkeys managed; the rest is changed on the portal
/// website.
struct SecuritySettingsView: View {
    @Environment(Session.self) private var session
    @State private var settings: SecuritySettings?
    @State private var loadError: String?

    var body: some View {
        Group {
            if let settings {
                SecuritySettingsList(settings: settings, accountHolderID: accountHolderID) {
                    self.settings = $0
                }
            } else if let loadError {
                ContentUnavailableView {
                    Label("Settings Unavailable", systemImage: "wifi.exclamationmark")
                } description: {
                    Text(loadError)
                } actions: {
                    Button("Try Again") {
                        Task { await load() }
                    }
                }
            } else {
                ProgressView("Loading settings…")
            }
        }
        .navigationTitle("Login & Security")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: accountHolderID) {
            await load()
        }
        .refreshable {
            await load()
        }
    }

    /// These belong to the signed-in adult, so they load the same whichever
    /// child is selected.
    private var accountHolderID: String {
        session.profile?.id ?? session.patientID
    }

    private func load() async {
        loadError = nil
        do {
            settings = try await session.service.securitySettings(for: accountHolderID)
        } catch {
            settings = nil
            loadError = error.localizedDescription
        }
    }
}

private struct SecuritySettingsList: View {
    let settings: SecuritySettings
    let accountHolderID: String
    let onChange: (SecuritySettings) -> Void

    @Environment(Session.self) private var session
    @Environment(\.openURL) private var openURL
    @State private var savingSwitch: SecuritySwitch?
    @State private var saveError: String?

    var body: some View {
        List {
            if settings.passwordChangeAvailable || settings.passkeysAvailable {
                Section("Login") {
                    if settings.passwordChangeAvailable, !settings.passwordLastChanged.isEmpty {
                        LabeledContent("Password Last Changed", value: settings.passwordLastChanged)
                    }
                    if settings.passkeysAvailable {
                        NavigationLink("Passkeys") {
                            PasskeysView(accountHolderID: accountHolderID)
                        }
                    }
                }
            }

            Section {
                SecurityStatusRow("Email or Text Message", isOn: settings.verifiesByEmailOrText)
                SecurityStatusRow("Authenticator App", isOn: settings.verifiesByAuthenticatorApp)
            } header: {
                Text("Two-Step Verification")
            } footer: {
                Text(settings.twoStepRequired
                     ? "A code from one of these is needed when you sign in. At least one must stay on."
                     : "A code from one of these adds a layer of security when you sign in.")
            }

            if settings.rememberDevicesAllowed {
                Section {
                    switchRow(.remembersDevices)
                } header: {
                    Text("Devices")
                } footer: {
                    Text("Remembered browsers need less identity verification when signing in to the portal.")
                }
            }

            Section {
                switchRow(.previewFeatures)
            } footer: {
                Text("Early access to new portal features. Some only appear the next time you sign in.")
            }

            Section {
                Button("Manage on Portal Website") {
                    openURL(MyChartConfig().url("app/security-settings"))
                }
            } footer: {
                Text("Change your password, two-step verification and remembered devices\(settings.deactivateAccountAllowed ? ", or deactivate your account," : "") on the portal website.")
            }
        }
        .alert(
            "Couldn’t Change Setting",
            isPresented: Binding(
                get: { saveError != nil },
                set: { if !$0 { saveError = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(saveError ?? "")
        }
    }

    /// A switch that saves to the portal straight away, showing a spinner
    /// while it does. On failure the switch stays where it was.
    private func switchRow(_ setting: SecuritySwitch) -> some View {
        Toggle(isOn: Binding(
            get: { settings[keyPath: setting.keyPath] },
            set: { isOn in Task { await save(setting, isOn: isOn) } }
        )) {
            HStack {
                Text(setting.title)
                if savingSwitch == setting {
                    Spacer()
                    ProgressView()
                }
            }
        }
        .disabled(savingSwitch != nil)
    }

    private func save(_ setting: SecuritySwitch, isOn: Bool) async {
        savingSwitch = setting
        defer { savingSwitch = nil }
        do {
            switch setting {
            case .previewFeatures:
                try await session.service.setPreviewFeatures(isOn, for: accountHolderID)
            case .remembersDevices:
                try await session.service.setRemembersDevices(isOn, for: accountHolderID)
            }
            var updated = settings
            updated[keyPath: setting.keyPath] = isOn
            onChange(updated)
        } catch {
            saveError = error.localizedDescription
        }
    }
}

/// The settings the app can switch on the portal.
private enum SecuritySwitch {
    case previewFeatures
    case remembersDevices

    var title: String {
        switch self {
        case .previewFeatures: "Preview Features"
        case .remembersDevices: "Remember Logged-In Devices"
        }
    }

    var keyPath: WritableKeyPath<SecuritySettings, Bool> {
        switch self {
        case .previewFeatures: \.previewFeaturesOn
        case .remembersDevices: \.remembersDevices
        }
    }
}

/// A setting shown as On, with a green tick, or Off.
private struct SecurityStatusRow: View {
    let title: String
    let isOn: Bool

    init(_ title: String, isOn: Bool) {
        self.title = title
        self.isOn = isOn
    }

    var body: some View {
        LabeledContent(title) {
            if isOn {
                Label("On", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(Theme.green)
            } else {
                Text("Off")
            }
        }
    }
}

// MARK: - Passkeys

/// The account holder's passkeys, which can be renamed and removed here.
/// Adding one happens in Safari: iOS only lets an app create a passkey for
/// a website that lists the app on its own server, and the portal can't
/// list this one.
struct PasskeysView: View {
    let accountHolderID: String

    @Environment(Session.self) private var session
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @State private var info: PasskeyInfo?
    @State private var loadError: String?
    @State private var renaming: Passkey?
    @State private var newName = ""
    @State private var removing: Passkey?
    /// A change waiting on the password, which the portal asks for again
    /// ten minutes after it was last entered.
    @State private var awaitingPassword: PasskeyChange?
    @State private var password = ""
    @State private var busyPasskeyID: String?
    @State private var actionError: String?
    /// Set while Safari is open to add a passkey, so the list reloads on return.
    @State private var isAddingInSafari = false

    var body: some View {
        Group {
            if let info {
                list(info)
            } else if let loadError {
                ContentUnavailableView {
                    Label("Passkeys Unavailable", systemImage: "wifi.exclamationmark")
                } description: {
                    Text(loadError)
                } actions: {
                    Button("Try Again") {
                        Task { await load() }
                    }
                }
            } else {
                ProgressView("Loading passkeys…")
            }
        }
        .navigationTitle("Passkeys")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: accountHolderID) {
            await load()
        }
        .refreshable {
            await load()
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active, isAddingInSafari else { return }
            isAddingInSafari = false
            Task { await load() }
        }
        .alert("Rename Passkey", isPresented: isPresent($renaming), presenting: renaming) { passkey in
            TextField("Name", text: $newName)
            Button("Cancel", role: .cancel) {}
            Button("Save") {
                let name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !name.isEmpty, name != passkey.name else { return }
                Task { await perform(.rename(passkey.id, name)) }
            }
        }
        .confirmationDialog(
            "Remove this passkey?",
            isPresented: isPresent($removing),
            titleVisibility: .visible,
            presenting: removing
        ) { passkey in
            Button("Remove “\(passkey.name)”", role: .destructive) {
                Task { await perform(.remove(passkey.id)) }
            }
        } message: { _ in
            Text("You won’t be able to sign in with it any more. It also stays in your password manager until you delete it there.")
        }
        .alert("Enter Your Password", isPresented: isPresent($awaitingPassword), presenting: awaitingPassword) { change in
            SecureField("Password", text: $password)
                .textContentType(.password)
            Button("Cancel", role: .cancel) { password = "" }
            Button("Continue") {
                Task { await verifyPassword(then: change) }
            }
        } message: { _ in
            Text("For your security, the portal needs your password before changing passkeys.")
        }
        .alert("Couldn’t Change Passkey", isPresented: isPresent($actionError)) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(actionError ?? "")
        }
    }

    private func list(_ info: PasskeyInfo) -> some View {
        List {
            Section {
                if info.passkeys.isEmpty {
                    Text("No passkeys yet")
                        .foregroundStyle(.secondary)
                }
                ForEach(info.passkeys) { passkey in
                    row(passkey)
                }
            } footer: {
                Text("Passkeys let you sign in with Face ID, Touch ID or your device passcode instead of a password, and skip two-step verification. They’re kept in a password manager like Apple Passwords.")
            }

            Section {
                Button("Add Passkey", systemImage: "plus") {
                    isAddingInSafari = true
                    openURL(MyChartConfig().url("app/passkey-management"))
                }
            } footer: {
                Text("Passkeys are added on the portal website in Safari, where you may need to sign in. iOS only lets the portal’s own website create them.")
            }
        }
    }

    private func row(_ passkey: Passkey) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(passkey.name)
                    .font(.headline)
                if let created = createdDescription(passkey) {
                    Text(created)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if busyPasskeyID == passkey.id {
                ProgressView()
            } else {
                Menu("Options", systemImage: "ellipsis.circle") {
                    renameButton(passkey)
                    removeButton(passkey)
                }
                .labelStyle(.iconOnly)
                .disabled(busyPasskeyID != nil)
            }
        }
        .swipeActions {
            removeButton(passkey)
            renameButton(passkey)
                .tint(.blue)
        }
        .contextMenu {
            renameButton(passkey)
            removeButton(passkey)
        }
    }

    private func renameButton(_ passkey: Passkey) -> some View {
        Button("Rename", systemImage: "pencil") {
            newName = passkey.name
            renaming = passkey
        }
    }

    private func removeButton(_ passkey: Passkey) -> some View {
        Button("Remove", systemImage: "trash", role: .destructive) {
            removing = passkey
        }
    }

    /// "Created 4 Oct 2026 at 7:24 pm with Mac - Safari", as on the portal.
    private func createdDescription(_ passkey: Passkey) -> String? {
        let date = passkey.created?.formatted(date: .abbreviated, time: .shortened)
        let device = passkey.createdOnDevice.isEmpty ? nil : passkey.createdOnDevice
        switch (date, device) {
        case let (date?, device?): return "Created \(date) with \(device)"
        case let (date?, nil): return "Created \(date)"
        case let (nil, device?): return "Created with \(device)"
        case (nil, nil): return nil
        }
    }

    private func load() async {
        loadError = nil
        do {
            info = try await session.service.passkeys(for: accountHolderID)
        } catch {
            info = nil
            loadError = error.localizedDescription
        }
    }

    /// Runs a change, first asking for the password if the portal's last
    /// check has run out.
    private func perform(_ change: PasskeyChange) async {
        guard let verifiedUntil = info?.verifiedUntil, verifiedUntil > .now else {
            password = ""
            awaitingPassword = change
            return
        }
        busyPasskeyID = change.passkeyID
        defer { busyPasskeyID = nil }
        do {
            switch change {
            case let .rename(id, name):
                let saved = try await session.service.renamePasskey(id, to: name, for: accountHolderID)
                if let index = info?.passkeys.firstIndex(where: { $0.id == id }) {
                    info?.passkeys[index].name = saved.name
                }
            case let .remove(id):
                try await session.service.removePasskey(id, for: accountHolderID)
                info?.passkeys.removeAll { $0.id == id }
            }
        } catch {
            actionError = error.localizedDescription
        }
    }

    private func verifyPassword(then change: PasskeyChange) async {
        let entered = password
        password = ""
        guard !entered.isEmpty else { return }
        busyPasskeyID = change.passkeyID
        do {
            let check = try await session.service.verifyPassword(entered, for: accountHolderID)
            busyPasskeyID = nil
            if check.mustSignOut {
                session.signOut()
                return
            }
            guard check.verified else {
                actionError = "That password isn’t right. Please try again."
                return
            }
            // The portal allows ten minutes; reloading picks up its exact
            // time, and the change then goes through without asking again.
            await load()
            if (info?.verifiedUntil ?? .distantPast) <= .now {
                info?.verifiedUntil = .now.addingTimeInterval(9 * 60)
            }
            await perform(change)
        } catch {
            busyPasskeyID = nil
            actionError = error.localizedDescription
        }
    }

    /// Presents an alert or dialog while `value` is set, clearing it on dismiss.
    private func isPresent<Value>(_ value: Binding<Value?>) -> Binding<Bool> {
        Binding(
            get: { value.wrappedValue != nil },
            set: { if !$0 { value.wrappedValue = nil } }
        )
    }
}

/// A passkey change, held while the portal asks for the password.
private enum PasskeyChange {
    case rename(String, String)
    case remove(String)

    var passkeyID: String {
        switch self {
        case let .rename(id, _), let .remove(id): id
        }
    }
}
