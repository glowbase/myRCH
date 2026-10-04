import SwiftUI

/// The account holder's contact details, as held by the portal. Read-only:
/// changes are made on the portal's Personal Information page.
struct PersonalInformationView: View {
    @Environment(Session.self) private var session
    @State private var information: PersonalInformation?
    @State private var loadError: String?

    var body: some View {
        Group {
            if let information {
                PersonalInformationList(information: information)
            } else if let loadError {
                ContentUnavailableView {
                    Label("Information Unavailable", systemImage: "wifi.exclamationmark")
                } description: {
                    Text(loadError)
                } actions: {
                    Button("Try Again") {
                        Task { await load() }
                    }
                }
            } else {
                ProgressView("Loading details…")
            }
        }
        .navigationTitle("Personal Information")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: accountHolderID) {
            await load()
        }
        .refreshable {
            await load()
        }
    }

    /// Like communication preferences, these are the signed-in adult's
    /// details, so they load the same whichever child is selected.
    private var accountHolderID: String {
        session.profile?.id ?? session.patientID
    }

    private func load() async {
        loadError = nil
        do {
            information = try await session.service.personalInformation(for: accountHolderID)
        } catch {
            information = nil
            loadError = error.localizedDescription
        }
    }
}

private struct PersonalInformationList: View {
    let information: PersonalInformation

    var body: some View {
        List {
            Section("Contact") {
                if !information.email.isEmpty {
                    PersonalInformationRow(
                        "Email",
                        symbol: "envelope.fill",
                        value: information.email,
                        needsVerification: information.emailNeedsVerification
                    )
                }
                ForEach(information.phoneNumbers) { phone in
                    let isMobile = phone.type.lowercased() == "mobile"
                    PersonalInformationRow(
                        phone.type.isEmpty ? "Phone" : phone.type.capitalized,
                        symbol: isMobile ? "iphone" : "phone.fill",
                        value: phone.number,
                        needsVerification: isMobile && information.mobileNeedsVerification
                    )
                }
            }

            if !information.addressLines.isEmpty {
                Section("Address") {
                    Label {
                        Text((information.addressLines + [information.country])
                            .filter { !$0.isEmpty }
                            .joined(separator: "\n"))
                            .textSelection(.enabled)
                    } icon: {
                        Image(systemName: "house.fill")
                    }
                }
            }

            Section {
                Link(destination: Self.portalURL) {
                    Label("Edit on the Portal", systemImage: "arrow.up.forward.square")
                }
            } footer: {
                Text("To change these details, update them on the portal or contact the hospital.")
            }
        }
    }

    private static let portalURL = URL(string: "https://myrchportal.rch.org.au/MyRCHPortal/app/personal-information")!
}

private struct PersonalInformationRow: View {
    let title: String
    let symbol: String
    let value: String
    let needsVerification: Bool

    init(_ title: String, symbol: String, value: String, needsVerification: Bool) {
        self.title = title
        self.symbol = symbol
        self.value = value
        self.needsVerification = needsVerification
    }

    var body: some View {
        LabeledContent {
            HStack(spacing: 6) {
                Text(value)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
                    .textSelection(.enabled)
                if needsVerification {
                    Image(systemName: "exclamationmark.circle.fill")
                        .foregroundStyle(.orange)
                        .accessibilityLabel("Needs verification")
                }
            }
        } label: {
            Label(title, systemImage: symbol)
        }
    }
}

#Preview {
    NavigationStack {
        PersonalInformationView()
    }
    .environment(Session())
}
