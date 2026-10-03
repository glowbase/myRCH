import Foundation
import WidgetKit

/// Keeps `WidgetSnapshot` current. Home hands over each child's portal
/// details (visit, UR number, allergies, what's new); the medication store
/// reports every dose change, from any source, so the widgets and Live
/// Activities follow along even when Home isn't open.
@MainActor
final class WidgetPublisher {
    static let shared = WidgetPublisher()

    static let showsAllergiesKey = "widgetShowsAllergies"

    private var snapshot = WidgetSnapshot.load() ?? WidgetSnapshot()
    private var pending: Task<Void, Never>?

    private init() {}

    /// From Home, after loading a child's portal data.
    func updateChild(id: String, name: String, urNumber: String?, nextVisit: WidgetSnapshot.Visit?,
                     allergies: [WidgetSnapshot.Allergy], allergiesKnown: Bool,
                     unreadMessages: Int, newResults: Int) {
        var child = snapshot.children[id] ?? WidgetSnapshot.Child(id: id, name: name, updated: .now)
        child.name = name
        child.urNumber = urNumber
        child.nextVisit = nextVisit
        child.allergies = allergies
        child.allergiesKnown = allergiesKnown
        child.unreadMessages = unreadMessages
        child.newResults = newResults
        child.updated = .now
        snapshot.children[id] = child
        snapshot.activeChildID = id
        publish()
    }

    /// From the medication store, whenever a dose, reminder or note changes.
    /// Debounced, so logging several at once reloads widgets once.
    func dosesChanged() {
        pending?.cancel()
        pending = Task {
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            publish()
        }
    }

    /// The Settings switch for showing allergies on the Lock Screen.
    func settingsChanged() { publish() }

    /// Signing out: nothing left for the widgets to show.
    func clear() {
        snapshot = WidgetSnapshot()
        WidgetSnapshot.remove()
        WidgetCenter.shared.reloadAllTimelines()
        ActivityManager.shared.endAll()
    }

    private func publish() {
        let store = MedicationStore.shared
        let calendar = Calendar.current
        for id in snapshot.children.keys {
            let today = store.todayDoses(patientID: id)
            snapshot.children[id]?.dosesDue = today.count
            snapshot.children[id]?.dosesLogged = today.filter { $0.status != nil }.count
            snapshot.children[id]?.upcomingDoses = today
                .filter { $0.status == nil && calendar.isDateInToday($0.time) }
                .map { WidgetSnapshot.Dose(medicine: $0.name, time: $0.time) }
        }
        snapshot.showsAllergiesOnLockScreen = UserDefaults.standard.bool(forKey: Self.showsAllergiesKey)
        snapshot.save()
        WidgetCenter.shared.reloadAllTimelines()
        ActivityManager.shared.refresh(snapshot)
        WatchBridge.shared.send(snapshot)
    }
}
