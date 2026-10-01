import Foundation
import Observation

/// Questions the family wants to ask at an upcoming visit: their own, and
/// any suggested by Apple Intelligence that they kept. Saved on this iPhone
/// only, per child and appointment.
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
    }

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

    static func key(patientID: String, appointmentID: String) -> String {
        "\(patientID)|\(appointmentID)"
    }

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
            list.append(Question(text: trimmed, isSuggested: suggested))
        }
        entries[key] = list
        save()
    }

    func toggleAsked(_ question: Question, in key: String) {
        guard let index = entries[key]?.firstIndex(where: { $0.id == question.id }) else { return }
        entries[key]?[index].isAsked.toggle()
        save()
    }

    func remove(_ question: Question, from key: String) {
        entries[key]?.removeAll { $0.id == question.id }
        if entries[key]?.isEmpty == true { entries[key] = nil }
        save()
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        try? data.write(to: fileURL, options: [.atomic, .completeFileProtection])
    }
}
