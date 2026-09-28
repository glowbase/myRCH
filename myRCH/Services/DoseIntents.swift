import AppIntents
import Foundation

// Actions behind the widget, Lock Screen, Control Centre and Live Activity
// buttons. The widget extension has a copy of each with the same name and
// parameters (see myRCHWidgets/WidgetIntents.swift); keep them in step.
// They run here, in the app: `LiveActivityIntent` lets the system launch the
// app in the background, and `.main` asks for the app as the target. So a
// dose logged from a widget clears its reminder and reaches the other parent,
// exactly like one logged in the app.

/// Logs every medication due at one time for a child: the widget's and Live
/// Activity's Taken and Skip buttons.
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

    @MainActor
    func perform() async throws -> some IntentResult {
        let store = MedicationStore.shared
        store.applyPendingDoseLogs()
        store.logAll(taken ? .taken : .skipped, in: MedicationStore.Slot(patientID: patientID, scheduled: scheduled))
        return .result()
    }
}

/// Logs the next dose due today as taken, for the child open in the app:
/// the Control Centre button.
struct LogNextDoseIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Log Next Dose"
    static let description = IntentDescription("Marks the next medication due today as taken.")
    static var allowedExecutionTargets: ExecutionTargets { .main }

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult {
        let store = MedicationStore.shared
        store.applyPendingDoseLogs()
        guard let child = WidgetSnapshot.load()?.child(), let slot = child.nextSlot else { return .result() }
        store.logAll(.taken, in: MedicationStore.Slot(patientID: child.id, scheduled: slot.time))
        return .result()
    }
}
