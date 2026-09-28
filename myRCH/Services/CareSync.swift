import CloudKit
import CryptoKit
import Foundation
import Observation

/// Where a medication's shared data lives: the child's zone and the
/// medication within it. Both are hashes, so neither the UR number nor the
/// medicine name appears in a zone or record name.
///
/// The portal gives every login its own ids for a child and their
/// medications, so two parents' phones can't match on those. The UR number
/// and the medicine's name are the same for both, so they're used instead.
nonisolated struct SyncRef: Codable, Hashable, Sendable {
    /// "child-<hash of UR number>"
    var zone: String
    /// Hash of the medicine's normalised name.
    var med: String

    var id: String { "\(zone)|\(med)" }

    static func zoneName(urNumber: String) -> String {
        "child-" + hash(urNumber.trimmingCharacters(in: .whitespaces))
    }

    static func medKey(name: String) -> String {
        hash(name.lowercased().split(whereSeparator: \.isWhitespace).joined(separator: " "))
    }

    private static func hash(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8)).prefix(12).map { String(format: "%02x", $0) }.joined()
    }
}

/// Shares medication reminders, the dose log and notes between parents
/// through CloudKit. The child's owner (whoever started sharing) keeps a
/// record zone in their private database, shared zone-wide with a CKShare;
/// the other parent sees it in their shared database. Two CKSyncEngines,
/// one per database, do the fetching, sending, retrying and push handling.
///
/// Only data kept on the device is shared this way. Anything the portal
/// holds (like the health goal) stays with the portal.
@MainActor
@Observable
final class CareSync: CKSyncEngineDelegate {
    static let shared = CareSync()
    nonisolated static let containerID = "iCloud.com.cooperbeltrami.myRCH"

    enum Role: String, Codable { case owner, participant }

    struct ZoneInfo: Codable, Hashable {
        var role: Role
        /// The zone owner's CloudKit user record name, part of the zone's id.
        var ownerName: String
    }

    /// Record kinds, by the first part of the record's name.
    enum Kind: String {
        case schedule = "s", dose = "d", asNeeded = "a", note = "n"

        var recordType: String {
            switch self {
            case .schedule: "Schedule"
            case .dose, .asNeeded: "Dose"
            case .note: "Note"
            }
        }
    }

    private struct Saved: Codable {
        var zones: [String: ZoneInfo] = [:]
        /// This phone's children, by portal patient id → zone name.
        var children: [String: String] = [:]
        /// Encoded system fields per "zone/recordName", so saves carry the
        /// server's change tag.
        var systemFields: [String: Data] = [:]
        var privateState: CKSyncEngine.State.Serialization?
        var sharedState: CKSyncEngine.State.Serialization?
    }

    private(set) var zones: [String: ZoneInfo] = [:]
    /// False until iCloud is confirmed available.
    private(set) var isAvailable = false

    @ObservationIgnored weak var store: MedicationStore?
    @ObservationIgnored private var saved = Saved()
    @ObservationIgnored private var privateEngine: CKSyncEngine?
    @ObservationIgnored private var sharedEngine: CKSyncEngine?
    @ObservationIgnored let container = CKContainer(identifier: CareSync.containerID)

    @ObservationIgnored private let fileURL: URL = {
        let folder = URL.applicationSupportDirectory
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appending(path: "care-sync.json")
    }()

    private init() {
        if let data = try? Data(contentsOf: fileURL),
           let decoded = try? JSONDecoder().decode(Saved.self, from: data) {
            saved = decoded
            zones = decoded.zones
        }
    }

    // MARK: Starting

    /// Starts the sync engines if iCloud is signed in. Safe to call more
    /// than once; call at launch.
    func start() async {
        guard privateEngine == nil else { return }
        let status = try? await container.accountStatus()
        isAvailable = status == .available
        guard isAvailable else { return }
        privateEngine = CKSyncEngine(CKSyncEngine.Configuration(
            database: container.privateCloudDatabase, stateSerialization: saved.privateState, delegate: self))
        sharedEngine = CKSyncEngine(CKSyncEngine.Configuration(
            database: container.sharedCloudDatabase, stateSerialization: saved.sharedState, delegate: self))
    }

    /// Fetches now rather than waiting for a push, e.g. on pull to refresh.
    func syncNow() async {
        try? await privateEngine?.fetchChanges()
        try? await sharedEngine?.fetchChanges()
    }

    // MARK: Children

    /// Remembers which zone this phone's child belongs to. Called when the
    /// child's UR number is known.
    func noteChild(patientID: String, zone: String) {
        guard saved.children[patientID] != zone else { return }
        saved.children[patientID] = zone
        persist()
    }

    func zone(forPatient patientID: String) -> String? { saved.children[patientID] }

    func role(forPatient patientID: String) -> Role? {
        zone(forPatient: patientID).flatMap { zones[$0]?.role }
    }

    // MARK: Changes from the store

    /// Queues a record to send, if its child is shared.
    func changed(_ kind: Kind, name: String, zone: String, deleted: Bool = false) {
        guard let info = zones[zone], let engine = engine(for: info.role) else { return }
        let recordID = CKRecord.ID(recordName: "\(kind.rawValue).\(name)", zoneID: zoneID(zone, info))
        engine.state.add(pendingRecordZoneChanges: [deleted ? .deleteRecord(recordID) : .saveRecord(recordID)])
    }

    /// Queues everything this phone has for a child's zone: on first
    /// sharing, and when joining someone else's share.
    private func uploadAll(zone: String) {
        guard let store else { return }
        for (kind, name) in store.recordNames(inZone: zone) {
            changed(kind, name: name, zone: zone)
        }
    }

    // MARK: Sharing

    enum SharingError: LocalizedError {
        case unavailable, unknownChild

        var errorDescription: String? {
            switch self {
            case .unavailable: "Sign in to iCloud in Settings to share reminders."
            case .unknownChild: "Open Home once for this child first, so the app knows their record."
            }
        }
    }

    /// Creates the child's zone and a zone-wide share (or returns the
    /// existing share), and queues this phone's data for it.
    func startSharing(patientID: String, childName: String) async throws -> CKShare {
        await start()
        guard isAvailable else { throw SharingError.unavailable }
        guard let zone = zone(forPatient: patientID) else { throw SharingError.unknownChild }
        let info = ZoneInfo(role: .owner, ownerName: CKCurrentUserDefaultName)
        let id = zoneID(zone, info)
        let database = container.privateCloudDatabase

        _ = try await database.modifyRecordZones(saving: [CKRecordZone(zoneID: id)], deleting: [])
        zones[zone] = info
        saved.zones = zones
        persist()
        uploadAll(zone: zone)

        if let existing = try? await database.record(for: CKRecord.ID(recordName: CKRecordNameZoneWideShare, zoneID: id)),
           let share = existing as? CKShare {
            return share
        }
        let share = CKShare(recordZoneID: id)
        share[CKShare.SystemFieldKey.title] = "\(childName)'s medication reminders"
        share.publicPermission = .none
        let results = try await database.modifyRecords(saving: [share], deleting: [])
        if case let .success(record)? = results.saveResults[share.recordID], let saved = record as? CKShare {
            return saved
        }
        return share
    }

    /// The child's share, if one exists (as owner or participant).
    func existingShare(patientID: String) async -> CKShare? {
        guard let zone = zone(forPatient: patientID), let info = zones[zone] else { return nil }
        let database = info.role == .owner ? container.privateCloudDatabase : container.sharedCloudDatabase
        let id = CKRecord.ID(recordName: CKRecordNameZoneWideShare, zoneID: zoneID(zone, info))
        return (try? await database.record(for: id)) as? CKShare
    }

    /// Owner: deletes the shared zone, which ends sharing for everyone.
    /// Participant: leaves the share. Either way this phone keeps its copy.
    func stopSharing(patientID: String) async throws {
        guard let zone = zone(forPatient: patientID), let info = zones[zone] else { return }
        let id = zoneID(zone, info)
        switch info.role {
        case .owner:
            _ = try await container.privateCloudDatabase.modifyRecordZones(saving: [], deleting: [id])
        case .participant:
            let shareID = CKRecord.ID(recordName: CKRecordNameZoneWideShare, zoneID: id)
            _ = try await container.sharedCloudDatabase.modifyRecords(saving: [], deleting: [shareID])
        }
        forget(zone: zone)
    }

    /// Called when this phone's user taps an invitation link.
    func accept(_ metadata: CKShare.Metadata) async {
        await start()
        _ = try? await container.accept(metadata)
        try? await sharedEngine?.fetchChanges()
    }

    // MARK: CKSyncEngineDelegate

    func handleEvent(_ event: CKSyncEngine.Event, syncEngine: CKSyncEngine) async {
        let isShared = syncEngine.database.databaseScope == .shared
        switch event {
        case .stateUpdate(let update):
            if isShared { saved.sharedState = update.stateSerialization } else { saved.privateState = update.stateSerialization }
            persist()

        case .accountChange(let change):
            switch change.changeType {
            case .signIn: break
            case .signOut, .switchAccounts: reset()
            @unknown default: break
            }

        case .fetchedDatabaseChanges(let changes):
            for modification in changes.modifications where modification.zoneID.zoneName.hasPrefix("child-") {
                let name = modification.zoneID.zoneName
                if isShared, zones[name] == nil {
                    // Joined someone else's share: add what this phone has.
                    zones[name] = ZoneInfo(role: .participant, ownerName: modification.zoneID.ownerName)
                    saved.zones = zones
                    persist()
                    uploadAll(zone: name)
                }
            }
            for deletion in changes.deletions {
                let name = deletion.zoneID.zoneName
                // Only forget a zone deleted from the database that holds it.
                if (zones[name]?.role == .participant) == isShared { forget(zone: name) }
            }

        case .fetchedRecordZoneChanges(let changes):
            for modification in changes.modifications {
                let record = modification.record
                let zone = record.recordID.zoneID.zoneName
                saved.systemFields[fieldsKey(record.recordID)] = Self.encodeSystemFields(record)
                store?.applyRemote(record, zone: zone)
            }
            for deletion in changes.deletions {
                saved.systemFields[fieldsKey(deletion.recordID)] = nil
                store?.applyRemoteDeletion(recordName: deletion.recordID.recordName,
                                           zone: deletion.recordID.zoneID.zoneName)
            }
            persist()

        case .sentRecordZoneChanges(let sent):
            for record in sent.savedRecords {
                saved.systemFields[fieldsKey(record.recordID)] = Self.encodeSystemFields(record)
            }
            for id in sent.deletedRecordIDs {
                saved.systemFields[fieldsKey(id)] = nil
            }
            for failure in sent.failedRecordSaves {
                let id = failure.record.recordID
                switch failure.error.code {
                case .serverRecordChanged:
                    // Both changed it: take the server's change tag and send
                    // ours again, so the most recent change wins.
                    if let server = failure.error.serverRecord {
                        saved.systemFields[fieldsKey(id)] = Self.encodeSystemFields(server)
                    }
                    syncEngine.state.add(pendingRecordZoneChanges: [.saveRecord(id)])
                case .zoneNotFound where !isShared:
                    syncEngine.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: id.zoneID))])
                    syncEngine.state.add(pendingRecordZoneChanges: [.saveRecord(id)])
                case .unknownItem:
                    saved.systemFields[fieldsKey(id)] = nil
                    syncEngine.state.add(pendingRecordZoneChanges: [.saveRecord(id)])
                case .zoneNotFound, .userDeletedZone:
                    forget(zone: id.zoneID.zoneName)
                default:
                    break
                }
            }
            persist()

        default:
            break
        }
    }

    func nextRecordZoneChangeBatch(_ context: CKSyncEngine.SendChangesContext,
                                   syncEngine: CKSyncEngine) async -> CKSyncEngine.RecordZoneChangeBatch? {
        let scope = context.options.scope
        let changes = syncEngine.state.pendingRecordZoneChanges.filter { scope.contains($0) }
        return await CKSyncEngine.RecordZoneChangeBatch(pendingChanges: changes) { recordID in
            await self.record(for: recordID, engine: syncEngine)
        }
    }

    /// Builds a record to send from the store's current data. Returns nil
    /// (and drops the change) when the item no longer exists.
    private func record(for id: CKRecord.ID, engine: CKSyncEngine) -> CKRecord? {
        let name = id.recordName
        guard let kind = Kind(rawValue: String(name.prefix { $0 != "." })) else { return nil }
        let record = saved.systemFields[fieldsKey(id)].flatMap(Self.decodeSystemFields)
            ?? CKRecord(recordType: kind.recordType, recordID: id)
        guard store?.fill(record, zone: id.zoneID.zoneName) == true else {
            engine.state.remove(pendingRecordZoneChanges: [.saveRecord(id)])
            return nil
        }
        return record
    }

    // MARK: Helpers

    private func engine(for role: Role) -> CKSyncEngine? {
        role == .owner ? privateEngine : sharedEngine
    }

    private func zoneID(_ zone: String, _ info: ZoneInfo) -> CKRecordZone.ID {
        CKRecordZone.ID(zoneName: zone, ownerName: info.ownerName)
    }

    private func fieldsKey(_ id: CKRecord.ID) -> String { "\(id.zoneID.zoneName)/\(id.recordName)" }

    private func forget(zone: String) {
        zones[zone] = nil
        saved.zones = zones
        saved.systemFields = saved.systemFields.filter { !$0.key.hasPrefix(zone + "/") }
        persist()
    }

    /// Signed out of iCloud or switched account: stop sharing on this phone,
    /// keeping its own copy of the data.
    private func reset() {
        zones = [:]
        saved = Saved(children: saved.children)
        privateEngine = nil
        sharedEngine = nil
        isAvailable = false
        persist()
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(saved) else { return }
        try? data.write(to: fileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    private static func encodeSystemFields(_ record: CKRecord) -> Data {
        let coder = NSKeyedArchiver(requiringSecureCoding: true)
        record.encodeSystemFields(with: coder)
        coder.finishEncoding()
        return coder.encodedData
    }

    private static func decodeSystemFields(_ data: Data) -> CKRecord? {
        guard let coder = try? NSKeyedUnarchiver(forReadingFrom: data) else { return nil }
        coder.requiresSecureCoding = true
        defer { coder.finishDecoding() }
        return CKRecord(coder: coder)
    }
}
