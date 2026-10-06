import CloudKit
import CryptoKit
import Foundation
import Observation

/// Questions the family wants to ask at an upcoming visit: their own, and
/// any suggested by Apple Intelligence that they kept. Saved on this iPhone
/// per child and appointment, and shared with the other parent through
/// CareSync when the child's reminders are shared.
@Observable
final class AppointmentQuestionsStore {
    static let shared = AppointmentQuestionsStore()

    struct Question: Identifiable, Hashable, Codable {
        var id = UUID()
        var text: String
        /// Ticked off once asked at the visit.
        var isAsked = false
        /// Written by Apple Intelligence rather than typed by the family.
        var isSuggested = false
        /// Keeps both parents' lists in the same order. Optional, as
        /// questions saved before sharing don't have it.
        var added: Date? = nil
    }

    /// By "patientID|appointment key".
    private var entries: [String: [Question]] = [:]

    /// Application Support, readable only while the phone is unlocked:
    /// questions can be about the child's health, and are only needed in
    /// the app.
    @ObservationIgnored private let fileURL: URL = {
        let folder = URL.applicationSupportDirectory
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appending(path: "appointment-questions.json")
    }()

    init() {
        if let data = try? Data(contentsOf: fileURL),
           let saved = try? JSONDecoder().decode([String: [Question]].self, from: data) {
            entries = saved
        }
    }

    // MARK: Keys

    /// The portal gives each parent's login its own appointment ids, so an
    /// appointment is matched between phones by its start (to the minute)
    /// and title instead, hashed so neither appears in CloudKit.
    static func appointmentKey(_ appointment: Appointment) -> String {
        let minute = Int((appointment.date.timeIntervalSince1970 / 60).rounded())
        let title = appointment.title.lowercased().split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return SHA256.hash(data: Data("\(minute)|\(title)".utf8))
            .prefix(12).map { String(format: "%02x", $0) }.joined()
    }

    static func key(patientID: String, appointment: Appointment) -> String {
        "\(patientID)|\(appointmentKey(appointment))"
    }

    /// Moves questions saved under an appointment's portal id (before they
    /// were shared) to its shared key, and sends them if the child is shared.
    func migrateLegacy(patientID: String, appointment: Appointment) {
        let legacy = "\(patientID)|\(appointment.id)"
        guard let old = entries.removeValue(forKey: legacy) else { return }
        let key = Self.key(patientID: patientID, appointment: appointment)
        var list = entries[key] ?? []
        for question in old where !list.contains(where: { $0.id == question.id }) {
            list.append(question)
            share(question, key: key)
        }
        entries[key] = list
        save()
    }

    // MARK: Editing

    func questions(for key: String) -> [Question] {
        entries[key] ?? []
    }

    /// Adds questions, skipping any already on the list (ignoring case).
    func add(_ texts: [String], suggested: Bool, to key: String) {
        var list = entries[key] ?? []
        for text in texts {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty,
                  !list.contains(where: { $0.text.caseInsensitiveCompare(trimmed) == .orderedSame })
            else { continue }
            let question = Question(text: trimmed, isSuggested: suggested, added: .now)
            list.append(question)
            share(question, key: key)
        }
        entries[key] = list
        save()
    }

    func toggleAsked(_ question: Question, in key: String) {
        guard let index = entries[key]?.firstIndex(where: { $0.id == question.id }) else { return }
        entries[key]?[index].isAsked.toggle()
        if let updated = entries[key]?[index] { share(updated, key: key) }
        save()
    }

    func remove(_ question: Question, from key: String) {
        entries[key]?.removeAll { $0.id == question.id }
        if entries[key]?.isEmpty == true { entries[key] = nil }
        share(question, key: key, deleted: true)
        save()
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        try? data.write(to: fileURL, options: [.atomic, .completeFileProtection])
    }

    // MARK: Sharing

    // Records are named "q.<appointment key>.<question id>" in the child's
    // zone, with the question's text and flags encrypted.

    /// Splits a local key into the patient and appointment key.
    private static func parts(of key: String) -> (patientID: String, appointment: String)? {
        let pieces = key.split(separator: "|", maxSplits: 1).map(String.init)
        return pieces.count == 2 ? (pieces[0], pieces[1]) : nil
    }

    /// Tells CareSync a question changed, if the child is shared.
    private func share(_ question: Question, key: String, deleted: Bool = false) {
        guard let (patientID, appointment) = Self.parts(of: key),
              let zone = CareSync.shared.zone(forPatient: patientID) else { return }
        CareSync.shared.changed(.question, name: "\(appointment).\(question.id.uuidString)",
                                zone: zone, deleted: deleted)
    }

    /// Local keys for an appointment in a child's zone (normally one).
    private func keys(zone: String, appointment: String) -> [String] {
        CareSync.shared.patients(inZone: zone).map { "\($0)|\(appointment)" }
    }

    /// Everything this phone holds for a child's zone, as record names.
    func recordNames(inZone zone: String) -> [(CareSync.Kind, String)] {
        let patients = Set(CareSync.shared.patients(inZone: zone))
        return entries.flatMap { key, questions -> [(CareSync.Kind, String)] in
            guard let (patientID, appointment) = Self.parts(of: key), patients.contains(patientID) else { return [] }
            return questions.map { (.question, "\(appointment).\($0.id.uuidString)") }
        }
    }

    /// The appointment key and question id in a record name.
    private static func ids(in recordName: String) -> (appointment: String, id: UUID)? {
        let pieces = recordName.split(separator: ".", maxSplits: 2).map(String.init)
        guard pieces.count == 3, pieces[0] == CareSync.Kind.question.rawValue,
              let id = UUID(uuidString: pieces[2]) else { return nil }
        return (pieces[1], id)
    }

    /// Fills a record from this phone's data. False if the question's gone.
    func fill(_ record: CKRecord, zone: String) -> Bool {
        guard let (appointment, id) = Self.ids(in: record.recordID.recordName),
              let question = keys(zone: zone, appointment: appointment).lazy
                .compactMap({ self.entries[$0]?.first { $0.id == id } }).first else { return false }
        let fields = record.encryptedValues
        fields["text"] = question.text
        fields["asked"] = question.isAsked ? 1 : 0
        fields["suggested"] = question.isSuggested ? 1 : 0
        fields["added"] = question.added
        return true
    }

    /// Applies a question the other parent added or changed. Not sent back.
    func applyRemote(_ record: CKRecord, zone: String) {
        guard let (appointment, id) = Self.ids(in: record.recordID.recordName) else { return }
        let fields = record.encryptedValues
        guard let text = fields["text"] as? String else { return }
        let question = Question(id: id, text: text,
                                isAsked: (fields["asked"] as? Int ?? 0) != 0,
                                isSuggested: (fields["suggested"] as? Int ?? 0) != 0,
                                added: fields["added"] as? Date)
        for key in keys(zone: zone, appointment: appointment) {
            var list = entries[key] ?? []
            if let index = list.firstIndex(where: { $0.id == id }) {
                list[index] = question
            } else {
                // In the order they were added, wherever that was.
                let index = list.firstIndex { ($0.added ?? .distantPast) > (question.added ?? .distantFuture) }
                list.insert(question, at: index ?? list.endIndex)
            }
            entries[key] = list
        }
        save()
    }

    /// Applies the other parent's deletion. Not sent back.
    func applyRemoteDeletion(recordName: String, zone: String) {
        guard let (appointment, id) = Self.ids(in: recordName) else { return }
        for key in keys(zone: zone, appointment: appointment) {
            entries[key]?.removeAll { $0.id == id }
            if entries[key]?.isEmpty == true { entries[key] = nil }
        }
        save()
    }
}
