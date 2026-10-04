import SwiftUI

/// The account holder's login, two-step verification and device settings,
/// as held by the portal. Read-only for now: the portal's requests for
/// changing them haven't been captured, so changes are made on the website.
struct SecuritySettingsView: View {
    @Environment(Session.self) private var session
    @State private var settings: SecuritySettings?
    @State private var loadError: String?

    var body: some View {
        Group {
            if let settings {
                SecuritySettingsList(settings: settings)
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
    @Environment(\.openURL) private var openURL

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
                    SecurityStatusRow("Remember Logged-In Devices", isOn: settings.remembersDevices)
                } header: {
                    Text("Devices")
                } footer: {
                    Text("Remembered browsers need less identity verification when signing in to the portal.")
                }
            }

            Section {
                SecurityStatusRow("Preview Features", isOn: settings.previewFeaturesOn)
            } footer: {
                Text("Early access to new portal features. Some only appear the next time you sign in.")
            }

            Section {
                Button("Manage on Portal Website") {
                    openURL(MyChartConfig().url("app/security-settings"))
                }
            } footer: {
                Text("Change your password, passkeys, two-step verification and devices\(settings.deactivateAccountAllowed ? ", or deactivate your account," : "") on the portal website.")
            }
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
