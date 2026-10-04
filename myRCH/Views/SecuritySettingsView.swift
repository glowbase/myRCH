import SwiftUI

/// The account holder's login, two-step verification and device settings,
/// as held by the portal. Preview features and remembered devices can be
/// switched here; the rest is changed on the portal website.
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
                        LabeledContent("Passkeys") {
                            Text("Face, fingerprint or PIN")
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
                Text("Change your password, passkeys, two-step verification and remembered devices\(settings.deactivateAccountAllowed ? ", or deactivate your account," : "") on the portal website.")
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
