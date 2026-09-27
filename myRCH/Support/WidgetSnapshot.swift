import Foundation

/// What the Home Screen widgets show, written by the app into the shared App
/// Group whenever Home loads or a dose is logged. The widget can't sign in to
/// the portal itself, so this is all it knows.
///
/// The app and the widget each have a copy of this file (one per target);
/// keep the two identical.
nonisolated struct WidgetSnapshot: Codable, Sendable {
    struct Visit: Codable, Sendable {
        var title: String
        var department: String
        var date: Date
        var isTelehealth: Bool
    }

    struct Dose: Codable, Sendable {
        var medicine: String
        var time: Date
    }

    /// First name only.
    var childName: String
    var nextVisit: Visit?
    /// Today's remaining scheduled doses, earliest first.
    var upcomingDoses: [Dose]
    var dosesDue: Int
    var dosesLogged: Int
    var updated: Date

    static let appGroup = "group.com.cooperbeltrami.myRCH"
    private static let fileName = "WidgetSnapshot.json"

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

    /// Signing out removes it, so the widget stops showing anything.
    static func remove() {
        guard let url = fileURL else { return }
        try? FileManager.default.removeItem(at: url)
    }
}
