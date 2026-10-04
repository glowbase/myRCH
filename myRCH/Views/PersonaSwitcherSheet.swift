import SwiftUI

/// Bottom sheet for switching between the signed-in person and any linked
/// accounts (e.g. a parent managing several children's records).
struct PersonaSwitcherSheet: View {
    let accounts: [LinkedAccount]
    @Binding var selectedID: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(Array(accounts.enumerated()), id: \.element.id) { index, account in
                        Button {
                            selectedID = account.id
                            dismiss()
                        } label: {
                            HStack(spacing: 14) {
                                AvatarView(initials: account.initials,
                                           tint: Theme.accountTint(account, at: index),
                                           size: 40)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(account.name)
                                        .font(.headline)
                                        .foregroundStyle(.primary)
                                    if account.unreadCount > 0 {
                                        Text("\(account.unreadCount) new update\(account.unreadCount == 1 ? "" : "s")")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                if account.id == selectedID {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(Theme.brand)
                                        .font(.title3)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                } header: {
                    Text("Viewing record for")
                }

                Section {
                    Button {
                        dismiss()
                    } label: {
                        Label("Manage linked accounts", systemImage: "person.2.badge.gearshape")
                    }
                }
            }
            .navigationTitle("Switch account")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}
