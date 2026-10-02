import CloudKit
import SwiftUI

/// What the iCloud share sheet shares: a child's reminders zone. Creates
/// the share the first time; after that, opens the existing one so the
/// owner can add or remove people.
struct ReminderShareItem: Transferable {
    let patientID: String
    let childName: String
    let existing: CKShare?
    let container = CKContainer(identifier: CareSync.containerID)

    static var transferRepresentation: some TransferRepresentation {
        CKShareTransferRepresentation { item in
            if let share = item.existing {
                return .existing(share, container: item.container)
            }
            return .prepareShare(container: item.container) {
                try await CareSync.shared.startSharing(patientID: item.patientID, childName: item.childName)
            }
        }
    }
}

/// Share a child's medication reminders, dose log and notes with another
/// parent through iCloud. They get the same reminders on their phone, and
/// doses either parent logs show on both.
struct SharedRemindersView: View {
    @Environment(Session.self) private var session
    @Environment(CareSync.self) private var careSync
    @State private var share: CKShare?
    @State private var isLoading = true
    @State private var confirmsStop = false
    @State private var errorText: String?
    @State private var observer: CKSystemSharingUIObserver?

    private var patientID: String { session.patientID }
    private var childName: String { session.activeAccount?.name ?? "your child" }
    private var role: CareSync.Role? { careSync.role(forPatient: patientID) }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    Image(systemName: "person.2.wave.2.fill")
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(Theme.medication, Theme.medication.lighter)
                        .font(.system(size: 40))
                    Text("Share \(childName)'s Reminders")
                        .font(.system(.title2, design: .rounded).bold())
                    Text("Another parent or carer gets the same medication reminders on their iPhone. Doses either of you log, your notes, and questions to ask at upcoming visits show on both.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 6)
            }

            if !careSync.isAvailable {
                Section {
                    Label("Sign in to iCloud in the Settings app to share reminders.", systemImage: "icloud.slash")
                        .foregroundStyle(.secondary)
                }
            } else if careSync.zone(forPatient: patientID) == nil {
                Section {
                    Label("Open Home for \(childName) first, so the app can match their record.", systemImage: "info.circle")
                        .foregroundStyle(.secondary)
                }
            } else {
                statusSection
                actionsSection
            }

            Section {
            } footer: {
                Text("Stored in iCloud and shared only with the people you invite. Medicine names, notes, questions and times are encrypted. The other person needs myRCH and their own My RCH Portal login with access to \(childName).")
            }
        }
        .navigationTitle("Share Reminders")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Sharing didn't work", isPresented: .constant(errorText != nil)) {
            Button("OK") { errorText = nil }
        } message: {
            Text(errorText ?? "")
        }
        .task(id: patientID) { await reload() }
        .refreshable { await reload() }
        .onAppear(perform: observeSharingSheet)
    }

    // MARK: Sections

    @ViewBuilder
    private var statusSection: some View {
        if isLoading {
            Section { ProgressView() }
        } else if let share {
            Section(role == .participant ? "Shared With You" : "People") {
                if role == .participant, let owner = share.owner.userIdentity.nameComponents {
                    Label("Shared by \(owner.formatted())", systemImage: "person.crop.circle.badge.checkmark")
                }
                ForEach(others(in: share), id: \.self) { participant in
                    HStack {
                        Label(name(of: participant), systemImage: "person.crop.circle")
                        Spacer()
                        Text(status(of: participant))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                if others(in: share).isEmpty && role == .owner {
                    Text("No one has joined yet.")
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private var actionsSection: some View {
        Section {
            if role != .participant {
                ShareLink(item: ReminderShareItem(patientID: patientID, childName: childName, existing: share),
                          preview: SharePreview("\(childName)'s reminders and visit questions",
                                                image: Image(systemName: "pills.fill"))) {
                    Label(share == nil ? "Invite Someone" : "Manage Sharing", systemImage: "person.badge.plus")
                }
            }
            if role != nil {
                Button(role == .owner ? "Stop Sharing" : "Leave", role: .destructive) {
                    confirmsStop = true
                }
                .confirmationDialog(role == .owner ? "Stop sharing \(childName)'s reminders?" : "Leave shared reminders?",
                                    isPresented: $confirmsStop, titleVisibility: .visible) {
                    Button(role == .owner ? "Stop Sharing" : "Leave", role: .destructive) {
                        Task { await stop() }
                    }
                } message: {
                    Text(role == .owner
                         ? "Everyone else stops getting updates. Each iPhone keeps what it has."
                         : "You stop getting updates. This iPhone keeps what it has.")
                }
            }
        }
    }

    // MARK: Helpers

    private func others(in share: CKShare) -> [CKShare.Participant] {
        share.participants.filter { $0.role != .owner && $0 != share.currentUserParticipant }
    }

    private func name(of participant: CKShare.Participant) -> String {
        participant.userIdentity.nameComponents?.formatted()
            ?? participant.userIdentity.lookupInfo?.emailAddress
            ?? participant.userIdentity.lookupInfo?.phoneNumber
            ?? "Invited person"
    }

    private func status(of participant: CKShare.Participant) -> String {
        switch participant.acceptanceStatus {
        case .accepted: "Joined"
        case .pending: "Invited"
        case .removed: "Removed"
        default: ""
        }
    }

    private func reload() async {
        await careSync.start()
        share = await careSync.existingShare(patientID: patientID)
        isLoading = false
    }

    private func stop() async {
        do {
            try await careSync.stopSharing(patientID: patientID)
            share = nil
        } catch {
            errorText = error.localizedDescription
        }
    }

    /// The system share sheet saves the share itself; refresh when it does.
    private func observeSharingSheet() {
        guard observer == nil else { return }
        let observer = CKSystemSharingUIObserver(container: CKContainer(identifier: CareSync.containerID))
        observer.systemSharingUIDidSaveShareBlock = { _, _ in
            Task { @MainActor in await reload() }
        }
        observer.systemSharingUIDidStopSharingBlock = { _, _ in
            Task { @MainActor in await reload() }
        }
        self.observer = observer
    }
}
