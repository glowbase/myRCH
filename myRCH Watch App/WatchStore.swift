import Foundation
import Observation
import WatchConnectivity

/// The Watch's copy of what the iPhone knows: the widget snapshot, sent over
/// Watch Connectivity whenever it changes on the phone and kept here so the
/// app still works away from the phone. Doses logged on the watch are shown
/// straight away and queued to the phone, which logs them properly (clearing
/// reminders and reaching the other parent through shared reminders).
@Observable
final class WatchStore: NSObject, WCSessionDelegate {
    static let shared = WatchStore()

    private(set) var snapshot: WidgetSnapshot?
    /// When the phone last sent anything.
    private(set) var received: Date?

    private static let savedKey = "watchSnapshot"
    private static let receivedKey = "watchSnapshotReceived"

    private override init() {
        super.init()
        if let data = UserDefaults.standard.data(forKey: Self.savedKey) {
            snapshot = try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
        }
        received = UserDefaults.standard.object(forKey: Self.receivedKey) as? Date
    }

    func activate() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    /// Logs a dose time: ticked off here at once, then sent to the phone.
    /// `transferUserInfo` is queued and delivered when the phone's reachable.
    func log(patientID: String, scheduled: Date, taken: Bool) {
        if var snapshot, var child = snapshot.children[patientID] {
            let due = child.upcomingDoses.filter { abs($0.time.timeIntervalSince(scheduled)) < 60 }.count
            child.upcomingDoses.removeAll { abs($0.time.timeIntervalSince(scheduled)) < 60 }
            child.dosesLogged += due
            snapshot.children[patientID] = child
            apply(snapshot)
        }
        WCSession.default.transferUserInfo([
            "patientID": patientID,
            "scheduled": scheduled.timeIntervalSince1970,
            "taken": taken
        ])
    }

    private func apply(_ snapshot: WidgetSnapshot) {
        self.snapshot = snapshot
        if let data = try? JSONEncoder().encode(snapshot) {
            UserDefaults.standard.set(data, forKey: Self.savedKey)
        }
    }

    private func receive(_ data: Data) {
        guard let snapshot = try? JSONDecoder().decode(WidgetSnapshot.self, from: data) else { return }
        apply(snapshot)
        received = .now
        UserDefaults.standard.set(received, forKey: Self.receivedKey)
    }

    // MARK: WCSessionDelegate

    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState,
                             error: (any Error)?) {
        // Whatever the phone sent while the app wasn't running.
        let data = session.receivedApplicationContext["snapshot"] as? Data
        if let data {
            Task { @MainActor in WatchStore.shared.receive(data) }
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        guard let data = applicationContext["snapshot"] as? Data else { return }
        Task { @MainActor in WatchStore.shared.receive(data) }
    }
}
