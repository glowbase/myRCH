import ActivityKit
import Foundation

// What each Live Activity shows. The app starts and updates them; the
// widget extension draws them. The app and the widget each have a copy of
// this file (one per target); keep the two identical.

/// A dose that's due: from an hour before until it's logged (or two
/// hours late), on the Lock Screen and in the Dynamic Island.
nonisolated struct DoseActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable, Sendable {
        var time: Date
        var medicines: [String]
        var logged: Int
        var due: Int
    }

    var patientID: String
    var childName: String
}

/// The day of a visit: counting down to the appointment, with where to go.
nonisolated struct VisitActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable, Sendable {
        var date: Date
    }

    var patientID: String
    var childName: String
    /// The appointment's id, for opening it.
    var visitID: String?
    var title: String
    var department: String
    var location: String?
    var isTelehealth: Bool
}
