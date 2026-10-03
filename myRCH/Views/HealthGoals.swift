import SwiftUI

/// Home's Health Goals: the one goal on the child's portal record, which
/// the care team can see (see `PortalGoal`).
struct HealthGoalsSection: View {
    @Environment(Session.self) private var session
    @State private var sharedGoal: PortalGoal?
    @State private var portalLoaded = false
    @State private var shareError: String?
    @State private var editsSharedGoal = false
    @State private var isSavingShared = false

    private let color = Color.green

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SummarySectionHeader<Feature>(title: "Health Goals")
            VStack(alignment: .leading, spacing: 14) {
                Label("Goals", systemImage: "target")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(color)

                if portalLoaded {
                    sharedGoalBlock
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: Theme.cardRadius))
        }
        .sheet(isPresented: $editsSharedGoal) {
            SharedGoalSheet(current: sharedGoal?.text ?? "") { text in
                Task { await saveSharedGoal(text) }
            }
        }
        .alert("Couldn't save the goal", isPresented: .constant(shareError != nil)) {
            Button("OK") { shareError = nil }
        } message: {
            Text(shareError ?? "")
        }
        .task(id: session.patientID) { await loadPortalGoals() }
    }

    /// The one goal on the portal record, which the care team can see.
    private var sharedGoalBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Shared with the care team")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            if let goal = sharedGoal {
                Text(goal.text)
                    .font(.system(.title3, design: .rounded).bold())
                    .fixedSize(horizontal: false, vertical: true)
                if let updated = goal.lastUpdated {
                    Text("Updated \(updated)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("No goal set")
                    .font(.system(.title3, design: .rounded).bold())
                Text("Set one goal on your child's record for the care team to see.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Button {
                editsSharedGoal = true
            } label: {
                if isSavingShared {
                    ProgressView()
                } else {
                    Label(sharedGoal == nil ? "Set Goal" : "Edit Goal", systemImage: "pencil")
                        .font(.subheadline.weight(.semibold))
                }
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
            .tint(color)
            .disabled(isSavingShared)
            .padding(.top, 2)
        }
    }

    private func loadPortalGoals() async {
        sharedGoal = (try? await session.service.patientGoals(for: session.patientID))?.first
        portalLoaded = true
    }

    /// If the portal's reply can't be read, check whether the goal changed
    /// anyway before reporting a failure.
    private func saveSharedGoal(_ text: String) async {
        isSavingShared = true
        defer { isSavingShared = false }
        do {
            try await session.service.setPatientGoal(text, for: session.patientID)
            await loadPortalGoals()
        } catch {
            await loadPortalGoals()
            // Cleared goals come back as no goal at all.
            if (sharedGoal?.text ?? "") != text {
                shareError = error.localizedDescription
            }
        }
    }
}

/// Sets the one free-text goal on the portal record, as the portal's own
/// Goals panel does. Saving replaces whatever was there.
private struct SharedGoalSheet: View {
    let current: String
    let onSave: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var confirmsRemove = false
    @FocusState private var focused: Bool

    private var trimmed: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("e.g. Weight gain", text: $text, axis: .vertical)
                        .lineLimit(2...6)
                        .focused($focused)
                } footer: {
                    Text(current.isEmpty
                         ? "Saved to your child's record in My RCH Portal, where the care team can see it."
                         : "Replaces the current goal on your child's record in My RCH Portal.")
                }
                // The portal clears the goal by saving it empty.
                if !current.isEmpty {
                    Section {
                        Button("Remove Goal", role: .destructive) { confirmsRemove = true }
                            .frame(maxWidth: .infinity)
                    }
                }
            }
            .confirmationDialog("Remove the shared goal?", isPresented: $confirmsRemove, titleVisibility: .visible) {
                Button("Remove Goal", role: .destructive) {
                    onSave("")
                    dismiss()
                }
            } message: {
                Text("It's removed from your child's record in My RCH Portal.")
            }
            .navigationTitle(current.isEmpty ? "Set Goal" : "Edit Goal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(trimmed)
                        dismiss()
                    }
                    .disabled(trimmed.isEmpty || trimmed == current)
                }
            }
            .onAppear {
                text = current
                focused = true
            }
        }
        .presentationDetents([.medium])
    }
}
