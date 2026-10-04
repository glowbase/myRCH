import SwiftUI

/// The account holder's contact details, as held by the portal. Email and
/// the mobile and work numbers can be changed here; the address and home
/// phone are read-only on the portal too.
struct PersonalInformationView: View {
    @Environment(Session.self) private var session
    @State private var information: PersonalInformation?
    @State private var loadError: String?
    @State private var isEditing = false

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
        .toolbar {
            if information != nil {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Edit") { isEditing = true }
                }
            }
        }
        .sheet(isPresented: $isEditing) {
            if let information {
                EditContactInformationView(information: information, accountHolderID: accountHolderID) {
                    self.information = $0
                }
            }
        }
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
                Section {
                    Label {
                        Text((information.addressLines + [information.country])
                            .filter { !$0.isEmpty }
                            .joined(separator: "\n"))
                            .textSelection(.enabled)
                    } icon: {
                        Image(systemName: "house.fill")
                    }
                } header: {
                    Text("Address")
                } footer: {
                    Text("To change your address or home phone, contact the hospital.")
                }
            }
        }
    }
}

/// Edits the details the portal lets the account holder change.
private struct EditContactInformationView: View {
    let information: PersonalInformation
    let accountHolderID: String
    let onSave: (PersonalInformation) -> Void

    @Environment(Session.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var update: ContactInformationUpdate
    @State private var isSaving = false
    @State private var saveError: String?

    init(information: PersonalInformation, accountHolderID: String,
         onSave: @escaping (PersonalInformation) -> Void) {
        self.information = information
        self.accountHolderID = accountHolderID
        self.onSave = onSave
        _update = State(initialValue: ContactInformationUpdate(
            email: information.email,
            mobilePhone: information.phone("mobile"),
            workPhone: information.phone("work")
        ))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Email", text: $update.email)
                        .keyboardType(.emailAddress)
                        .textContentType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } header: {
                    Text("Email")
                } footer: {
                    Text("Portal notifications are sent here.")
                }

                Section {
                    LabeledContent("Mobile") {
                        TextField("Mobile", text: $update.mobilePhone)
                            .keyboardType(.phonePad)
                            .textContentType(.telephoneNumber)
                            .multilineTextAlignment(.trailing)
                    }
                    LabeledContent("Work") {
                        TextField("Optional", text: $update.workPhone)
                            .keyboardType(.phonePad)
                            .textContentType(.telephoneNumber)
                            .multilineTextAlignment(.trailing)
                    }
                } header: {
                    Text("Phone")
                } footer: {
                    Text("Leave a number blank to remove it.")
                }
            }
            .navigationTitle("Edit Contact Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView()
                    } else {
                        Button("Save") {
                            Task { await save() }
                        }
                        .fontWeight(.semibold)
                        .disabled(!canSave)
                    }
                }
            }
            .interactiveDismissDisabled(isSaving || hasChanges)
            .alert(
                "Couldn’t Save Details",
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
    }

    private var trimmed: ContactInformationUpdate {
        ContactInformationUpdate(
            email: update.email.trimmingCharacters(in: .whitespacesAndNewlines),
            mobilePhone: update.mobilePhone.trimmingCharacters(in: .whitespacesAndNewlines),
            workPhone: update.workPhone.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    private var hasChanges: Bool {
        trimmed != ContactInformationUpdate(
            email: information.email,
            mobilePhone: information.phone("mobile"),
            workPhone: information.phone("work")
        )
    }

    /// The portal needs an email; a rough shape check catches typos early.
    private var canSave: Bool {
        let email = trimmed.email
        return hasChanges && email.contains("@") && email.contains(".")
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        do {
            let saved = try await session.service.updateContactInformation(trimmed, for: accountHolderID)
            onSave(saved)
            dismiss()
        } catch {
            saveError = error.localizedDescription
        }
    }
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
