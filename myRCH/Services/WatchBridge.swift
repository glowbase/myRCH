import Foundation
import WatchConnectivity

/// Talks to the Apple Watch app. The watch can't sign in to the portal or
/// read the widgets' App Group, so the iPhone sends it the same snapshot the
/// widgets use whenever it changes, and the watch sends back the doses logged
/// on it. Application context holds only the latest snapshot, which is all
/// the watch needs; logged doses use `transferUserInfo`, which is queued and
/// delivered even if the phone isn't reachable when they're tapped.
final class WatchBridge: NSObject, WCSessionDelegate {
    static let shared = WatchBridge()

    static let snapshotKey = "snapshot"

    private override init() {}

    /// Call once at launch.
    func activate() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    /// The widget snapshot, for the watch to show.
    func send(_ snapshot: WidgetSnapshot) {
        let session = WCSession.default
        guard WCSession.isSupported(), session.activationState == .activated,
              session.isPaired, session.isWatchAppInstalled,
              let data = try? JSONEncoder().encode(snapshot) else { return }
        try? session.updateApplicationContext([Self.snapshotKey: data])
    }

    // MARK: WCSessionDelegate

    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState,
                             error: (any Error)?) {
        // Send what the watch should show as soon as the link is up.
        guard activationState == .activated else { return }
        Task { @MainActor in
            if let snapshot = WidgetSnapshot.load() { WatchBridge.shared.send(snapshot) }
        }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    /// Switched to another watch: reconnect to it.
    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        WCSession.default.activate()
    }

    /// A dose logged on the watch.
    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        guard let patientID = userInfo["patientID"] as? String,
              let stamp = userInfo["scheduled"] as? Double,
              let taken = userInfo["taken"] as? Bool else { return }
        Task { @MainActor in
            let slot = MedicationStore.Slot(patientID: patientID, scheduled: Date(timeIntervalSince1970: stamp))
            MedicationStore.shared.logAll(taken ? .taken : .skipped, in: slot)
        }
    }
}
