import SwiftUI

struct CommunicationPreferencesView: View {
    @Environment(Session.self) private var session
    @State private var preferences: CommunicationPreferences?
    @State private var savedPreferences: CommunicationPreferences?
    @State private var loadError: String?
    @State private var saveError: String?
    @State private var isSaving = false

    var body: some View {
        Group {
            if let preferences {
                CommunicationPreferencesList(
                    preferences: Binding(
                        get: { self.preferences ?? preferences },
                        set: { self.preferences = $0 }
                    )
                )
            } else if let loadError {
                ContentUnavailableView {
                    Label("Preferences Unavailable", systemImage: "wifi.exclamationmark")
                } description: {
                    Text(loadError)
                } actions: {
                    Button("Try Again") {
                        Task { await load() }
                    }
                }
            } else {
                ProgressView("Loading preferences…")
            }
        }
        .navigationTitle("Communication Preferences")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if isSaving {
                ToolbarItem(placement: .topBarTrailing) {
                    ProgressView()
                }
            }
        }
        .alert(
            "Couldn’t Save Preferences",
            isPresented: Binding(
                get: { saveError != nil },
                set: { if !$0 { saveError = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(saveError ?? "")
        }
        .task(id: accountHolderID) {
            await load()
        }
        // Auto-save: wait for a short pause in toggling, then send the
        // latest state. A new change cancels the wait and restarts it.
        .task(id: preferences) {
            guard hasChanges else { return }
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled else { return }
            // Unstructured, so a later toggle doesn't cancel a request in flight.
            Task { await saveLatest() }
        }
    }

    /// Preferences belong to the signed-in adult, and the portal only returns
    /// them in that account's context, so use it even while a child is selected.
    private var accountHolderID: String {
        session.profile?.id ?? session.patientID
    }

    private var hasChanges: Bool {
        guard let preferences, let savedPreferences else { return false }
        return preferences != savedPreferences
    }

    private func load() async {
        loadError = nil
        do {
            let loaded = try await session.service.communicationPreferences(for: accountHolderID)
            preferences = loaded
            savedPreferences = loaded
        } catch {
            preferences = nil
            savedPreferences = nil
            loadError = error.localizedDescription
        }
    }

    /// Saves until the portal matches what's on screen. Toggles made while a
    /// save is running are picked up by the next pass of the loop.
    private func saveLatest() async {
        guard !isSaving else { return }
        isSaving = true
        defer { isSaving = false }
        while let current = preferences, current != savedPreferences {
            do {
                try await session.service.updateCommunicationPreferences(current, for: accountHolderID)
                savedPreferences = current
            } catch {
                // Put the switches back to what the portal actually has.
                preferences = savedPreferences
                saveError = error.localizedDescription
                return
            }
        }
    }
}

private struct CommunicationPreferencesList: View {
    @Binding var preferences: CommunicationPreferences
    @State private var selectedGroupID: String?

    var body: some View {
        List {
            CommunicationContactSection(contact: preferences.contactInformation)

            if preferences.groups.isEmpty {
                Section {
                    Text("No notification settings were found for this account.")
                        .foregroundStyle(.secondary)
                }
            } else {
                Section("Notifications") {
                    ForEach(preferences.groups) { group in
                        Button {
                            selectedGroupID = group.id
                        } label: {
                            CommunicationGroupRow(group: group)
                        }
                        .tint(.primary)
                    }
                }
            }
        }
        .sheet(isPresented: Binding(
            get: { selectedGroupID != nil },
            set: { if !$0 { selectedGroupID = nil } }
        )) {
            if let index = preferences.groups.firstIndex(where: { $0.id == selectedGroupID }) {
                CommunicationGroupSheet(group: $preferences.groups[index])
            }
        }
    }
}

private struct CommunicationGroupRow: View {
    let group: CommunicationPreferenceGroup

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(color.gradient, in: .rect(cornerRadius: 7))
            VStack(alignment: .leading, spacing: 2) {
                Text(group.title)
                if !group.description.isEmpty {
                    Text(group.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Text("\(enabledCount) of \(group.items.count) on")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
    }

    /// Settings with at least one channel switched on.
    private var enabledCount: Int {
        group.items.filter { $0.channels.contains { $0.status != .off } }.count
    }

    private var symbol: String {
        switch group.title.lowercased() {
        case "messages": "envelope.fill"
        case "health": "heart.text.square.fill"
        case "appointments": "calendar"
        case "account management": "person.crop.circle.fill"
        case "questionnaires": "list.clipboard.fill"
        case "care companion": "checklist"
        default: "bell.fill"
        }
    }

    private var color: Color {
        switch group.title.lowercased() {
        case "messages": .blue
        case "health": .pink
        case "appointments": .red
        case "account management": .gray
        case "questionnaires": .orange
        case "care companion": .green
        default: .indigo
        }
    }
}

private struct CommunicationGroupSheet: View {
    @Binding var group: CommunicationPreferenceGroup
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if !group.description.isEmpty {
                    Section {
                        Text(group.description)
                            .foregroundStyle(.secondary)
                    }
                }

                // One section per setting keeps its switches clearly apart
                // from the next setting's title.
                ForEach($group.items) { $item in
                    Section {
                        ForEach($item.channels) { $channel in
                            CommunicationChannelToggle(channel: $channel)
                        }
                    } header: {
                        Text(item.title)
                    } footer: {
                        if !item.description.isEmpty {
                            Text(item.description)
                        }
                    }
                }
            }
            .navigationTitle(group.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

private struct CommunicationContactSection: View {
    let contact: CommunicationContactInformation

    var body: some View {
        Section {
            if !contact.email.isEmpty {
                LabeledContent {
                    HStack(spacing: 6) {
                        Text(contact.email)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.trailing)
                        if contact.emailPending {
                            Image(systemName: "clock.fill")
                                .foregroundStyle(.orange)
                                .accessibilityLabel("Verification pending")
                        }
                    }
                } label: {
                    Label("Email", systemImage: "envelope.fill")
                }
            }

            if !contact.mobilePhone.isEmpty {
                LabeledContent {
                    HStack(spacing: 6) {
                        Text(contact.mobilePhone)
                            .foregroundStyle(.secondary)
                        if contact.mobileIsVerified && !contact.mobilePending {
                            Image(systemName: "checkmark.seal.fill")
                                .foregroundStyle(.green)
                                .accessibilityLabel("Verified")
                        } else if contact.mobilePending {
                            Image(systemName: "clock.fill")
                                .foregroundStyle(.orange)
                                .accessibilityLabel("Verification pending")
                        }
                    }
                } label: {
                    Label("Mobile", systemImage: "iphone")
                }
            }
        } header: {
            Text("Contact Details")
        } footer: {
            Text("Notifications are sent to the contact details held by the portal.")
        }
    }
}

private struct CommunicationChannelToggle: View {
    @Binding var channel: CommunicationChannel

    var body: some View {
        Toggle(isOn: isOn) {
            Label(channel.kind.title, systemImage: channel.kind.symbol)
        }
        .disabled(channel.status == .unavailable)
        .accessibilityHint(channel.status == .unavailable ? "This setting is required by the portal." : "")
    }

    private var isOn: Binding<Bool> {
        Binding(
            get: { channel.status != .off },
            set: { channel.status = $0 ? .on : .off }
        )
    }
}

#Preview {
    NavigationStack {
        CommunicationPreferencesView()
    }
    .environment(Session())
}
