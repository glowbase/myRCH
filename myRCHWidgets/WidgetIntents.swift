import AppIntents
import Foundation
import WidgetKit

// The widget's copies of the app's dose intents (see myRCH/Services/
// DoseIntents.swift): same names and parameters, so the buttons below can
// use them. The system runs the app's copy (`.main`). If it runs this one
// instead, the tap is queued for the app and shown straight away.

struct LogDoseIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Log Dose"
    static let description = IntentDescription("Marks a medication time as taken or skipped.")
    static var allowedExecutionTargets: ExecutionTargets { .main }
    static let isDiscoverable = false

    @Parameter(title: "Child") var patientID: String
    @Parameter(title: "Dose Time") var scheduled: Date
    @Parameter(title: "Taken") var taken: Bool

    init() {}

    init(patientID: String, scheduled: Date, taken: Bool) {
        self.patientID = patientID
        self.scheduled = scheduled
        self.taken = taken
    }

    func perform() async throws -> some IntentResult {
        PendingDoseLogs.queue(patientID: patientID, scheduled: scheduled, taken: taken)
        return .result()
    }
}

struct LogNextDoseIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Log Next Dose"
    static let description = IntentDescription("Marks the next medication due today as taken.")
    static var allowedExecutionTargets: ExecutionTargets { .main }

    init() {}

    func perform() async throws -> some IntentResult {
        if let child = WidgetSnapshot.load()?.child(), let slot = child.nextSlot {
            PendingDoseLogs.queue(patientID: child.id, scheduled: slot.time, taken: true)
        }
        return .result()
    }
}

extension PendingDoseLogs {
    /// Saves the tap for the app, and ticks it off in the widgets now.
    static func queue(patientID: String, scheduled: Date, taken: Bool) {
        var logs = load()
        logs.entries.append(Entry(patientID: patientID, scheduled: scheduled, taken: taken, loggedAt: .now))
        logs.save()
        if var snapshot = WidgetSnapshot.load(), var child = snapshot.children[patientID] {
            let due = child.upcomingDoses.filter { abs($0.time.timeIntervalSince(scheduled)) < 60 }.count
            child.upcomingDoses.removeAll { abs($0.time.timeIntervalSince(scheduled)) < 60 }
            child.dosesLogged += due
            snapshot.children[patientID] = child
            snapshot.save()
        }
        WidgetCenter.shared.reloadAllTimelines()
    }
}

// MARK: - Choosing the child

/// A child whose record is on this phone, for "Edit Widget".
struct ChildEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Child"
    static let defaultQuery = ChildQuery()

    let id: String
    let name: String

    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(name)") }
}

struct ChildQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [ChildEntity] {
        let children = WidgetSnapshot.load()?.children ?? [:]
        return identifiers.compactMap { id in children[id].map { ChildEntity(id: $0.id, name: $0.name) } }
    }

    func suggestedEntities() async throws -> [ChildEntity] {
        (WidgetSnapshot.load()?.children.values ?? [:].values)
            .sorted { $0.name < $1.name }
            .map { ChildEntity(id: $0.id, name: $0.name) }
    }
}

/// Every widget's configuration: which child it shows. Left empty, it
/// follows the child open in the app.
struct SelectChildIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Choose Child"
    static let description = IntentDescription("Choose whose details this widget shows.")

    @Parameter(title: "Child") var child: ChildEntity?

    init() {}
}
