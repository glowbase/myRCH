import Foundation

// MARK: - Core domain models
//
// These loosely mirror the shape of FHIR resources (Patient, Appointment,
// Observation, MedicationRequest, Communication) so a real Epic FHIR / SMART
// on FHIR backend can be mapped onto them without changing the UI layer.

/// The signed-in person, plus any linked proxy accounts (e.g. a parent
/// managing a child's record — mirrors the account switcher in the portal).
struct PatientProfile: Identifiable, Hashable {
    let id: String
    var fullName: String
    var preferredName: String
    var initials: String
    /// Linked accounts this user can act on behalf of.
    var linkedAccounts: [LinkedAccount]
}

struct LinkedAccount: Identifiable, Hashable {
    let id: String
    var name: String
    var initials: String
    var unreadCount: Int
}

// MARK: - Appointments

struct Appointment: Identifiable, Hashable {
    enum Status: Hashable {
        case scheduled
        case completed
        case missed
        case cancelled
    }

    let id: String
    var title: String
    var department: String
    var provider: String?
    var date: Date
    var status: Status
    var isTelehealth: Bool
    var hasVisitSummary: Bool
}

// MARK: - Test results

struct TestResult: Identifiable, Hashable {
    enum Kind: Hashable {
        case lab
        case imaging
        case pathology
    }

    let id: String
    var name: String
    var date: Date
    var kind: Kind
    var orderingProvider: String
    var isUnread: Bool
    /// Short human-readable interpretation, when available.
    var summary: String?
}

// MARK: - Medications

struct Medication: Identifiable, Hashable {
    let id: String
    var name: String
    var dose: String
    var instructions: String
    var prescriber: String
    var isActive: Bool
}

// MARK: - Messages

struct Message: Identifiable, Hashable {
    let id: String
    var subject: String
    var sender: String
    var preview: String
    var date: Date
    var isUnread: Bool
}

// MARK: - Health summary

struct HealthIssue: Identifiable, Hashable {
    let id: String
    var name: String
    var notedDate: Date?
}

struct Allergy: Identifiable, Hashable {
    let id: String
    var substance: String
    var reaction: String
    var severity: String
}

struct Immunisation: Identifiable, Hashable {
    let id: String
    var name: String
    var date: Date
}
