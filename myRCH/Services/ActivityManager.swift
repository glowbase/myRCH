import ActivityKit
import Foundation

/// Starts, updates and ends the Live Activities from the widget snapshot,
/// each time it's republished (a dose logged anywhere, Home loaded, the app
/// opened).
///
/// iOS only lets an app *start* a Live Activity while it's open (or while
/// running one of its Live Activity intents), so a dose or visit that comes
/// up while the app is closed appears the next time it's opened. Updating
/// and ending work any time, so a dose the other parent logs still clears.
@MainActor
final class ActivityManager {
    static let shared = ActivityManager()
    static let enabledKey = "liveActivitiesEnabled"

    /// Shown from an hour before a dose until two hours after it.
    private static let doseLead: TimeInterval = 60 * 60
    private static let doseGrace: TimeInterval = 2 * 60 * 60
    /// Visit-day activity: from six hours before to an hour after.
    private static let visitLead: TimeInterval = 6 * 60 * 60
    private static let visitGrace: TimeInterval = 60 * 60

    private var isEnabled: Bool {
        (UserDefaults.standard.object(forKey: Self.enabledKey) as? Bool ?? true)
            && ActivityAuthorizationInfo().areActivitiesEnabled
    }

    private init() {}

    func refresh(_ snapshot: WidgetSnapshot) {
        guard isEnabled else {
            endAll()
            return
        }
        let now = Date.now
        for child in snapshot.children.values {
            refreshDose(child, now: now)
            refreshVisit(child, now: now)
        }
        // Children no longer on this phone.
        for activity in Activity<DoseActivityAttributes>.activities
        where snapshot.children[activity.attributes.patientID] == nil {
            end(activity)
        }
    }

    func endAll() {
        Activity<DoseActivityAttributes>.activities.forEach(end)
        Activity<VisitActivityAttributes>.activities.forEach(end)
    }

    // MARK: Doses

    private func refreshDose(_ child: WidgetSnapshot.Child, now: Date) {
        let existing = Activity<DoseActivityAttributes>.activities.filter { $0.attributes.patientID == child.id }
        guard let slot = child.nextSlot,
              slot.time.timeIntervalSince(now) <= Self.doseLead,
              now.timeIntervalSince(slot.time) <= Self.doseGrace else {
            existing.forEach(end)
            return
        }
        let state = DoseActivityAttributes.ContentState(time: slot.time, medicines: slot.medicines,
                                                        logged: child.dosesLogged, due: child.dosesDue)
        let content = ActivityContent(state: state, staleDate: slot.time.addingTimeInterval(Self.doseGrace))
        if let activity = existing.first {
            if activity.content.state != state {
                Task { await activity.update(content) }
            }
            existing.dropFirst().forEach(end)
        } else {
            _ = try? Activity.request(attributes: DoseActivityAttributes(patientID: child.id, childName: child.name),
                                      content: content)
        }
    }

    // MARK: Visits

    private func refreshVisit(_ child: WidgetSnapshot.Child, now: Date) {
        let existing = Activity<VisitActivityAttributes>.activities.filter { $0.attributes.patientID == child.id }
        guard let visit = child.nextVisit,
              Calendar.current.isDate(visit.date, inSameDayAs: now),
              visit.date.timeIntervalSince(now) <= Self.visitLead,
              now.timeIntervalSince(visit.date) <= Self.visitGrace else {
            existing.forEach(end)
            return
        }
        // Another visit replaced the one shown: start afresh.
        let matching = existing.filter { $0.attributes.title == visit.title && $0.content.state.date == visit.date }
        let keep = Set(matching.map(\.id))
        existing.filter { !keep.contains($0.id) }.forEach(end)
        guard matching.isEmpty else { return }
        let attributes = VisitActivityAttributes(patientID: child.id, childName: child.name,
                                                 visitID: visit.id, title: visit.title,
                                                 department: visit.department, location: visit.location,
                                                 isTelehealth: visit.isTelehealth)
        _ = try? Activity.request(attributes: attributes,
                                  content: ActivityContent(state: .init(date: visit.date),
                                                           staleDate: visit.date.addingTimeInterval(Self.visitGrace)))
    }

    private func end(_ activity: Activity<DoseActivityAttributes>) {
        Task { await activity.end(nil, dismissalPolicy: .immediate) }
    }

    private func end(_ activity: Activity<VisitActivityAttributes>) {
        Task { await activity.end(nil, dismissalPolicy: .immediate) }
    }
}
