import Foundation

/// What the widgets, Lock Screen widgets, controls and Live Activities show,
/// written by the app into the shared App Group. The widget can't sign in to
/// the portal, so this is all it knows: saved per child whenever Home loads
/// for them, and whenever a dose is logged (here, from a widget, or by the
/// other parent through shared reminders).
///
/// The app, the widget and the Watch app each have a copy of this file (one
/// per target); keep them identical. (The Watch gets it from the iPhone over
/// Watch Connectivity, so the App Group parts do nothing there.)
nonisolated struct WidgetSnapshot: Codable, Sendable {
    struct Visit: Codable, Sendable, Hashable {
        /// The appointment's id, for opening it from a widget.
        var id: String? = nil
        var title: String
        var department: String
        var date: Date
        var isTelehealth: Bool
        /// Where to check in, e.g. "Specialist Clinics, Desk A1".
        var location: String?
    }

    struct Dose: Codable, Sendable, Hashable {
        var medicine: String
        var time: Date
    }

    struct Allergy: Codable, Sendable, Hashable {
        var substance: String
        var reaction: String
    }

    struct Child: Codable, Sendable, Identifiable, Hashable {
        /// The portal patient id this phone uses for the child.
        var id: String
        /// First name only.
        var name: String
        var urNumber: String?
        var nextVisit: Visit?
        /// Today's scheduled doses still to log, earliest first.
        var upcomingDoses: [Dose] = []
        var dosesDue = 0
        var dosesLogged = 0
        var allergies: [Allergy] = []
        var unreadMessages = 0
        var newResults = 0
        /// When the portal data (visit, results, messages) was last loaded.
        var updated: Date

        /// The next time something's due, and everything due then.
        var nextSlot: (time: Date, medicines: [String])? {
            guard let first = upcomingDoses.first else { return nil }
            let medicines = upcomingDoses.filter { abs($0.time.timeIntervalSince(first.time)) < 60 }.map(\.medicine)
            return (first.time, medicines)
        }
    }

    var children: [String: Child] = [:]
    /// The child last open in the app; widgets without a chosen child show them.
    var activeChildID: String?
    /// Chosen in Settings: allergies are shown on the Lock Screen widget
    /// without unlocking, so they're off unless turned on.
    var showsAllergiesOnLockScreen = false

    /// A widget's chosen child, else the one open in the app.
    func child(_ id: String? = nil) -> Child? {
        if let id, let child = children[id] { return child }
        if let active = activeChildID, let child = children[active] { return child }
        return children.values.sorted { $0.name < $1.name }.first
    }

    static let appGroup = "group.com.glowbase.myRCH"
    private static let fileName = "WidgetSnapshot-v2.json"

    private static var fileURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup)?
            .appending(path: fileName)
    }

    static func load() -> WidgetSnapshot? {
        guard let url = fileURL, let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
    }

    /// Readable after the first unlock, so Lock Screen widgets still work.
    func save() {
        guard let url = Self.fileURL, let data = try? JSONEncoder().encode(self) else { return }
        try? data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    /// Signing out removes it, so the widgets stop showing anything.
    static func remove() {
        guard let url = fileURL else { return }
        try? FileManager.default.removeItem(at: url)
        // The first version's file, if still there.
        if let old = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup)?
            .appending(path: "WidgetSnapshot.json") {
            try? FileManager.default.removeItem(at: old)
        }
    }
}

/// Doses logged from a widget or control when the app couldn't be reached.
/// The app applies and clears them when it next runs. (Normally the log
/// intents run inside the app, and this stays empty.)
nonisolated struct PendingDoseLogs: Codable, Sendable {
    struct Entry: Codable, Sendable, Hashable {
        var patientID: String
        var scheduled: Date
        var taken: Bool
        var loggedAt: Date
    }

    var entries: [Entry] = []

    private static var fileURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: WidgetSnapshot.appGroup)?
            .appending(path: "PendingDoseLogs.json")
    }

    static func load() -> PendingDoseLogs {
        guard let url = fileURL, let data = try? Data(contentsOf: url),
              let logs = try? JSONDecoder().decode(PendingDoseLogs.self, from: data) else { return PendingDoseLogs() }
        return logs
    }

    func save() {
        guard let url = Self.fileURL, let data = try? JSONEncoder().encode(self) else { return }
        try? data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
}
