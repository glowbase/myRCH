import Foundation

/// Short-lived, in-memory store for portal responses. Kept in memory only:
/// health data isn't written to disk, and nothing survives a relaunch.
actor ResponseCache {
    /// How long a response stays fresh before the next read refetches it.
    static let lifetime: TimeInterval = 5 * 60

    private struct Entry {
        let value: any Sendable
        let expires: Date
    }

    private var entries: [String: Entry] = [:]
    /// Requests in progress, so simultaneous reads of the same data (e.g. the
    /// dashboard and a list row) share one network call.
    private var inFlight: [String: Task<any Sendable, Error>] = [:]
    /// Bumped by `removeAll()`, so a request that finishes after a refresh
    /// doesn't put stale data back.
    private var generation = 0

    /// The cached value for `key` if still fresh; otherwise fetches, stores
    /// and returns it. Failures aren't cached, so the next read retries.
    func value<T: Sendable>(_ key: String, fetch: @escaping @Sendable () async throws -> T) async throws -> T {
        if let entry = entries[key], entry.expires > .now, let value = entry.value as? T {
            return value
        }
        if let running = inFlight[key], let value = try await running.value as? T {
            return value
        }

        let started = generation
        let task = Task<any Sendable, Error> { try await fetch() }
        inFlight[key] = task
        defer { if generation == started { inFlight[key] = nil } }

        let fetched = try await task.value
        if generation == started {
            entries[key] = Entry(value: fetched, expires: .now.addingTimeInterval(Self.lifetime))
        }
        guard let value = fetched as? T else { throw PortalError.network }
        return value
    }

    /// Forgets entries whose key starts with any of `prefixes`, after an
    /// action changes that data on the portal.
    func remove(prefixes: [String]) {
        for key in entries.keys where prefixes.contains(where: key.hasPrefix) {
            entries[key] = nil
        }
        for key in inFlight.keys where prefixes.contains(where: key.hasPrefix) {
            inFlight[key] = nil
        }
    }

    /// Forgets everything: on pull to refresh, sign-in, sign-out and when
    /// switching between live and demo data.
    func removeAll() {
        entries.removeAll()
        inFlight.removeAll()
        generation += 1
    }
}

/// Wraps any backend with `ResponseCache`. Views keep talking to a plain
/// `PortalService`; repeat visits within five minutes don't hit the portal.
/// Keys include the patient, so each child's data is cached separately.
struct CachedPortalService: PortalService {
    let base: PortalService
    let cache: ResponseCache

    private func cached<T: Sendable>(_ key: String, _ fetch: @escaping @Sendable () async throws -> T) async throws -> T {
        try await cache.value(key, fetch: fetch)
    }

    func signIn(username: String, password: String) async throws -> PatientProfile {
        try await base.signIn(username: username, password: password)
    }

    func recordHeader(for patientID: String) async throws -> RecordHeader {
        try await cached("recordHeader|\(patientID)") { try await base.recordHeader(for: patientID) }
    }

    func appointments(for patientID: String) async throws -> [Appointment] {
        try await cached("appointments|\(patientID)") { try await base.appointments(for: patientID) }
    }

    func visitDocuments(appointmentID: String, for patientID: String) async throws -> [VisitDocument] {
        try await cached("visitDocuments|\(patientID)|\(appointmentID)") {
            try await base.visitDocuments(appointmentID: appointmentID, for: patientID)
        }
    }

    func visitDocumentHTML(_ document: VisitDocument, for patientID: String) async throws -> String {
        try await cached("visitDocumentHTML|\(patientID)|\(document.id)") {
            try await base.visitDocumentHTML(document, for: patientID)
        }
    }

    func letters(for patientID: String) async throws -> [Letter] {
        try await cached("letters|\(patientID)") { try await base.letters(for: patientID) }
    }

    func letterHTML(_ letter: Letter, for patientID: String) async throws -> String {
        try await cached("letterHTML|\(patientID)|\(letter.id)") { try await base.letterHTML(letter, for: patientID) }
    }

    func testResults(for patientID: String) async throws -> [TestResult] {
        try await cached("testResults|\(patientID)") { try await base.testResults(for: patientID) }
    }

    func testResultDetails(_ result: TestResult, for patientID: String) async throws -> TestResult {
        try await cached("testResultDetails|\(patientID)|\(result.id)") {
            try await base.testResultDetails(result, for: patientID)
        }
    }

    /// Scans and PDFs can be large, so they aren't held in memory.
    func documentData(_ document: ResultDocument, for patientID: String) async throws -> Data {
        try await base.documentData(document, for: patientID)
    }

    func medications(for patientID: String) async throws -> [Medication] {
        try await cached("medications|\(patientID)") { try await base.medications(for: patientID) }
    }

    /// Search-as-you-type results aren't worth keeping.
    func searchMedications(_ text: String, for patientID: String) async throws -> [MedicationSearchResult] {
        try await base.searchMedications(text, for: patientID)
    }

    func addMedication(named name: String, startDate: Date, for patientID: String) async throws {
        do {
            try await base.addMedication(named: name, startDate: startDate, for: patientID)
        } catch {
            await cache.remove(prefixes: ["medications|\(patientID)"])
            throw error
        }
        await cache.remove(prefixes: ["medications|\(patientID)"])
    }

    func removeMedication(_ medication: Medication, for patientID: String) async throws {
        do {
            try await base.removeMedication(medication, for: patientID)
        } catch {
            await cache.remove(prefixes: ["medications|\(patientID)"])
            throw error
        }
        await cache.remove(prefixes: ["medications|\(patientID)"])
    }

    func messages(for patientID: String) async throws -> [Message] {
        try await cached("messages|\(patientID)") { try await base.messages(for: patientID) }
    }

    func conversations(in folder: MessageFolder, for patientID: String) async throws -> [Conversation] {
        try await cached("conversations|\(patientID)|\(folder.rawValue)") {
            try await base.conversations(in: folder, for: patientID)
        }
    }

    func conversation(id: String, for patientID: String) async throws -> Conversation {
        try await cached("conversation|\(patientID)|\(id)") { try await base.conversation(id: id, for: patientID) }
    }

    func setConversationsBookmarked(_ isBookmarked: Bool, ids: [String], for patientID: String) async throws {
        try await changingConversations(patientID) {
            try await base.setConversationsBookmarked(isBookmarked, ids: ids, for: patientID)
        }
    }

    func setConversationsUnread(_ isUnread: Bool, ids: [String], for patientID: String) async throws {
        try await changingConversations(patientID) {
            try await base.setConversationsUnread(isUnread, ids: ids, for: patientID)
        }
    }

    func moveConversationsToTrash(ids: [String], for patientID: String) async throws {
        try await changingConversations(patientID) {
            try await base.moveConversationsToTrash(ids: ids, for: patientID)
        }
    }

    func restoreConversationsFromTrash(ids: [String], for patientID: String) async throws {
        try await changingConversations(patientID) {
            try await base.restoreConversationsFromTrash(ids: ids, for: patientID)
        }
    }

    func sendReply(_ text: String, attachments: [MessageAttachment], in conversation: Conversation,
                   includeOtherViewers: Bool, for patientID: String) async throws {
        try await changingConversations(patientID) {
            try await base.sendReply(text, attachments: attachments, in: conversation,
                                     includeOtherViewers: includeOtherViewers, for: patientID)
        }
    }

    /// Uploads aren't cached.
    func uploadAttachment(_ data: Data, fileName: String, mimeType: String,
                          for patientID: String) async throws -> MessageAttachment {
        try await base.uploadAttachment(data, fileName: fileName, mimeType: mimeType, for: patientID)
    }

    /// Runs an action, then forgets cached conversations — even when it
    /// fails, since some of several may already have gone through.
    private func changingConversations(_ patientID: String, _ action: () async throws -> Void) async throws {
        do {
            try await action()
        } catch {
            await forgetConversations(patientID)
            throw error
        }
        await forgetConversations(patientID)
    }

    /// The folders, the dashboard's latest messages and opened threads all
    /// change when a conversation is bookmarked, marked or moved.
    private func forgetConversations(_ patientID: String) async {
        await cache.remove(prefixes: ["conversations|\(patientID)", "messages|\(patientID)", "conversation|\(patientID)|"])
    }

    func careTeam(for patientID: String) async throws -> [CareTeamMember] {
        try await cached("careTeam|\(patientID)") { try await base.careTeam(for: patientID) }
    }

    func growthCharts(for patientID: String) async throws -> [GrowthDataset] {
        try await cached("growth|\(patientID)") { try await base.growthCharts(for: patientID) }
    }

    func healthIssues(for patientID: String) async throws -> [HealthIssue] {
        try await cached("healthIssues|\(patientID)") { try await base.healthIssues(for: patientID) }
    }

    func allergies(for patientID: String) async throws -> [Allergy] {
        try await cached("allergies|\(patientID)") { try await base.allergies(for: patientID) }
    }

    var readsAllergies: Bool { base.readsAllergies }

    func immunisations(for patientID: String) async throws -> [Immunisation] {
        try await cached("immunisations|\(patientID)") { try await base.immunisations(for: patientID) }
    }

    func patientGoals(for patientID: String) async throws -> [PortalGoal] {
        try await cached("goals|\(patientID)") { try await base.patientGoals(for: patientID) }
    }

    func setPatientGoal(_ text: String, for patientID: String) async throws {
        do {
            try await base.setPatientGoal(text, for: patientID)
        } catch {
            await cache.remove(prefixes: ["goals|\(patientID)"])
            throw error
        }
        await cache.remove(prefixes: ["goals|\(patientID)"])
    }

    func setEarlierVisitAlerts(_ isOn: Bool, appointmentID: String, for patientID: String) async throws {
        try await base.setEarlierVisitAlerts(isOn, appointmentID: appointmentID, for: patientID)
    }

    func exploreMore(for patientID: String) async throws -> ExploreMoreFeed {
        try await cached("exploreMore|\(patientID)") { try await base.exploreMore(for: patientID) }
    }

    func immunisationDoses(vaccineID: String, for patientID: String) async throws -> [ImmunisationDose] {
        try await cached("immunisationDoses|\(patientID)|\(vaccineID)") {
            try await base.immunisationDoses(vaccineID: vaccineID, for: patientID)
        }
    }
}
