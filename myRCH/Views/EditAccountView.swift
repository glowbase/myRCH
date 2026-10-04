import SwiftUI

/// The linked accounts, each opening its editor. Reached from Settings.
struct EditAccountsView: View {
    @Environment(Session.self) private var session

    var body: some View {
        List {
            Section {
                ForEach(Array((session.profile?.linkedAccounts ?? []).enumerated()), id: \.element.id) { index, account in
                    NavigationLink {
                        EditAccountView(account: account, index: index)
                    } label: {
                        HStack(spacing: 14) {
                            AvatarView(initials: account.initials,
                                       tint: Theme.accountTint(account, at: index),
                                       size: 34)
                            Text(account.name)
                        }
                    }
                }
            } footer: {
                Text("Names and colours are saved to the portal, so they show there too.")
            }
        }
        .navigationTitle("Names and Colours")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Renames a linked account and picks its colour, like the portal's Family
/// Access page.
struct EditAccountView: View {
    let account: LinkedAccount
    /// Position in the list, for the fallback colour when none is set.
    let index: Int

    @Environment(Session.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var colour: Int?
    @State private var isSaving = false
    @State private var errorMessage: String?

    init(account: LinkedAccount, index: Int) {
        self.account = account
        self.index = index
        _name = State(initialValue: account.name)
        _colour = State(initialValue: account.tabColor)
    }

    private var tint: Color {
        colour.map { Theme.accountColours[$0] } ?? Theme.accountTint(account, at: index)
    }

    private var initials: String {
        let parts = name.split(separator: " ").prefix(2)
        let text = parts.compactMap(\.first).map(String.init).joined().uppercased()
        return text.isEmpty ? account.initials : text
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var hasChanges: Bool {
        trimmedName != account.name || colour != account.tabColor
    }

    var body: some View {
        Form {
            Section {
                AvatarView(initials: initials, tint: tint, size: 80)
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
            }

            Section {
                TextField("Patient's own name", text: $name)
                    .textContentType(.name)
                    .submitLabel(.done)
            } header: {
                Text("Name")
            } footer: {
                Text("Leave blank to use the patient's own name.")
            }

            Section("Colour scheme") {
                colourPicker
            }
        }
        .navigationTitle(account.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                if isSaving {
                    ProgressView()
                } else {
                    Button("Save", action: save)
                        .disabled(!hasChanges)
                }
            }
        }
        .alert("Couldn't save", isPresented: .init(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    /// A row of swatches with a tick on the chosen one, as on the portal.
    private var colourPicker: some View {
        HStack(spacing: 0) {
            ForEach(Theme.accountColours.indices, id: \.self) { option in
                Button {
                    colour = option
                } label: {
                    Circle()
                        .fill(Theme.accountColours[option])
                        .frame(width: 36, height: 36)
                        .overlay {
                            if option == colour {
                                Image(systemName: "checkmark")
                                    .font(.body.weight(.bold))
                                    .foregroundStyle(.white)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Theme.accountColourNames[option])
                .accessibilityAddTraits(option == colour ? .isSelected : [])
            }
        }
        .padding(.vertical, 6)
    }

    private func save() {
        // The portal needs a colour: its first (blue) if none was ever set.
        let chosen = colour ?? 0
        isSaving = true
        Task {
            defer { isSaving = false }
            do {
                try await session.customiseAccount(account.id, name: trimmedName, colour: chosen)
                dismiss()
            } catch {
                errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
    }
}
