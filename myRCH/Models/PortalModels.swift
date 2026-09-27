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
    var dateOfBirth: Date? = nil
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

    var durationMinutes: Int = 30
    var address: String? = nil
    var phone: String? = nil
    /// Where to report on arrival, e.g. a clinic desk.
    var checkInLocation: String? = nil
    /// Preparation steps shown before the visit.
    var instructions: [String] = []
    /// After Visit Summary text for past appointments.
    var visitSummary: String? = nil

    var endDate: Date { date.addingTimeInterval(TimeInterval(durationMinutes * 60)) }
}

/// A letter the hospital has shared (clinic letters, referrals, notes).
struct Letter: Identifiable, Hashable {
    /// The letter's note id (`hnoId`), used with `csn` to load it.
    let id: String
    var csn: String
    var date: Date
    /// The portal's letter type, e.g. "Referral Letter", "Parent Absence".
    var reason: String
    var author: String?
    var isUnread: Bool

    /// Letter-template names ("Send Notes", "Paste Notes", "Blank") describe
    /// how staff created the letter, not what it's about, so they read as
    /// plain "Letter".
    var title: String {
        let templates: Set<String> = ["send notes", "paste notes", "blank"]
        return templates.contains(reason.lowercased()) || reason.isEmpty ? "Letter" : reason
    }
}

/// A document the portal renders for a past visit, fetched on demand.
struct VisitDocument: Identifiable, Hashable {
    enum Kind: Hashable {
        /// The patient-facing summary: vitals, next steps, medications.
        case afterVisitSummary
        /// A clinician's progress note ("Notes from the Care Team").
        case careTeamNotes
    }

    let id: String
    var kind: Kind
    var title: String
    /// e.g. the note's author; shown under the title.
    var author: String? = nil
    var date: Date? = nil
    /// Sent as-is to LoadReportContent: `reportID`, `csn`, and the
    /// document's context keys (`contextLang`, or `contextID` /
    /// `contextDAT` / `contextINI`), as the portal supplies them.
    var reportParameters: [String: String]
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
    /// When the specimen was collected.
    var date: Date
    var kind: Kind
    /// The clinician who ordered the test.
    var orderingProvider: String
    var isUnread: Bool
    /// Short human-readable interpretation, when available (e.g. imaging reports).
    var summary: String?

    /// Individual measured values (e.g. Haemoglobin, Platelets).
    var components: [ResultComponent] = []
    var documents: [ResultDocument] = []
    var comments: [ResultComment] = []
    var specimen: String? = nil
    var authorisingClinician: String? = nil
    var resultDate: Date? = nil
    var status: String = "Final"
    var resultingLab: String? = nil
    /// The portal's own abnormal flag, for results loaded without components.
    var isFlaggedAbnormal: Bool = false

    /// True when the portal flags the result or any measured value falls
    /// outside its normal range.
    var isAbnormal: Bool { isFlaggedAbnormal || components.contains(where: \.isAbnormal) }

    enum RangeStatus: Hashable {
        case within, outside
    }

    /// Nil when there's nothing to compare against (cultures, imaging, or
    /// details not loaded yet), so no "within range" claim is made for them.
    var rangeStatus: RangeStatus? {
        if isAbnormal { return .outside }
        let hasRange = components.contains { $0.value != nil && ($0.normalLow != nil || $0.normalHigh != nil) }
        return hasRange ? .within : nil
    }

    /// Newest first. Many results from one collection share a timestamp, so
    /// break ties by name, then id, to keep the order stable across reloads.
    nonisolated static func newestFirst(_ a: TestResult, _ b: TestResult) -> Bool {
        if a.date != b.date { return a.date > b.date }
        if a.name != b.name { return a.name.localizedStandardCompare(b.name) == .orderedAscending }
        return a.id < b.id
    }
}

/// A single measured value within a test result, with its reference range.
struct ResultComponent: Identifiable, Hashable {
    let id: String
    var name: String
    /// Nil when the result isn't a plain number (e.g. "<5", "Negative").
    var value: Double?
    var unit: String
    var normalLow: Double?
    var normalHigh: Double?
    /// The value as the portal displays it, when it differs from `value`.
    var valueText: String? = nil
    /// The portal's range text, for ranges that aren't two numbers.
    var rangeText: String? = nil
    /// The portal's own abnormal flag (High, Low, Abnormal…).
    var isFlaggedAbnormal: Bool = false
    /// Set for censored values such as "<1" or ">500": `value` is the bound,
    /// and the true value lies somewhere beyond it.
    var qualifier: Qualifier? = nil

    /// Nonisolated so the portal decoder (a background actor) can compare it.
    nonisolated enum Qualifier: Hashable {
        case lessThan, greaterThan
    }

    var isAbnormal: Bool {
        if isFlaggedAbnormal { return true }
        guard let value else { return false }
        switch qualifier {
        case nil:
            if let normalLow, value < normalLow { return true }
            if let normalHigh, value > normalHigh { return true }
            return false
        // Only flag what's certain: "<3" is low against a range starting at
        // 10, but "<30" might be anywhere, so it isn't flagged.
        case .lessThan:
            return normalLow.map { value <= $0 } ?? false
        case .greaterThan:
            return normalHigh.map { value >= $0 } ?? false
        }
    }
}

/// One organism grown in a culture, parsed from a culture component's text:
/// "Organism 1\nStaphylococcus aureus\nColony Count Qualitative: moderate".
struct CultureOrganism: Hashable {
    /// Semi-quantitative colony count, least to most.
    enum Growth: Int, CaseIterable, Comparable {
        case scant = 1, light, moderate, heavy

        static func < (a: Growth, b: Growth) -> Bool { a.rawValue < b.rawValue }

        var label: String {
            switch self {
            case .scant: "Scant"
            case .light: "Light"
            case .moderate: "Moderate"
            case .heavy: "Heavy"
            }
        }

        /// Maps the lab's wording, including common synonyms, onto the scale.
        /// Pure text matching, so callable from any isolation.
        nonisolated init?(text: String) {
            let text = text.lowercased()
            if ["scant", "rare", "very light", "very few"].contains(where: text.contains) { self = .scant }
            else if ["heavy", "numerous", "profuse", "many", "large"].contains(where: text.contains) { self = .heavy }
            else if text.contains("moderate") { self = .moderate }
            else if ["light", "few", "small"].contains(where: text.contains) { self = .light }
            else { return nil }
        }
    }

    var name: String
    /// Nil when the count's wording isn't recognised; `growthText` still shows.
    var growth: Growth?
    var growthText: String?
}

extension ResultComponent {
    /// The organism this component reports, if it's a culture line.
    var organism: CultureOrganism? {
        guard let text = valueText else { return nil }
        let lines = text.components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        // Culture lines lead with "Organism <n>"; anything else ("No growth")
        // stays an ordinary text result.
        guard let first = lines.first, first.lowercased().hasPrefix("organism") else { return nil }
        var rest = Array(lines.dropFirst())
        var growthText: String?
        if let index = rest.firstIndex(where: { $0.lowercased().hasPrefix("colony count") }) {
            let line = rest.remove(at: index)
            growthText = line.split(separator: ":", maxSplits: 1).last
                .map { $0.trimmingCharacters(in: .whitespaces) }
        }
        guard let name = rest.first else { return nil }
        return CultureOrganism(name: name,
                               growth: growthText.flatMap(CultureOrganism.Growth.init(text:)),
                               growthText: growthText)
    }
}

/// A scanned or accompanying document attached to a result.
struct ResultDocument: Identifiable, Hashable {
    let id: String
    var title: String
    /// Nil when unknown until the file is downloaded.
    var pageCount: Int? = 1
    /// Portal-relative download path. Nil for mock documents.
    var downloadPath: String? = nil
}

/// A note from a clinician about a result.
struct ResultComment: Identifiable, Hashable {
    let id: String
    var author: String
    var date: Date?
    var text: String
}

// MARK: - Medications

struct Medication: Identifiable, Hashable {
    let id: String
    var name: String
    var dose: String
    var instructions: String
    var prescriber: String
    var isActive: Bool

    enum Form: Hashable {
        case tablet, capsule, liquid, inhaled, injection, topical
    }

    /// Brand or common name, e.g. "Hypersal".
    var commonName: String? = nil
    var form: Form = .tablet
    var prescribedDate: Date? = nil
    var approvedBy: String? = nil
    /// e.g. "100 sachets"
    var quantity: String? = nil
    var daySupply: Int? = nil
    /// Whether a repeat can be requested through the portal.
    var canRequestRepeat: Bool = false
    /// Added by the family rather than prescribed; awaits clinician review.
    var isPatientReported: Bool = false
}

/// A private note the family keeps about medication.
struct MedicationNote: Identifiable, Hashable, Codable {
    let id: UUID
    var text: String
    var date: Date
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

// MARK: - Growth

/// One set of measurements taken at a visit.
/// A growth reference set, e.g. "WHO Girls (0–2 years)", with its charts.
struct GrowthDataset: Identifiable, Hashable {
    let id: String
    var name: String
    /// e.g. "WHO Child Growth Standards".
    var source: String
    var charts: [GrowthChart]
    /// Demo data uses approximate curves; the portal's are the official ones.
    var isSample: Bool = false
}

/// One chart (e.g. Weight for Age) in a reference set: its percentile
/// curves, and the child's measurements with their percentiles.
struct GrowthChart: Identifiable, Hashable {
    /// The chart kind, e.g. "weightForAge". The same across data sets, so a
    /// chart chosen in one set stays chosen when switching to another.
    let kind: String
    var title: String
    /// Axis labels as given, with units, e.g. "Age (months)", "Weight (kg)".
    var xLabel: String
    var yLabel: String
    var xRange: ClosedRange<Double>
    var yRange: ClosedRange<Double>
    /// Percentile curves, lowest first.
    var curves: [GrowthCurve]
    /// The child's measurements on this chart, oldest first.
    var points: [GrowthPoint]

    var id: String { kind }
    /// Age on the x axis (not length, as in Weight for Length).
    var isAgeBased: Bool { xLabel.localizedCaseInsensitiveContains("age") }
}

struct GrowthCurve: Identifiable, Hashable {
    struct Point: Hashable {
        var x: Double
        var y: Double
    }
    /// e.g. 50 for the median.
    var percentile: Double
    var points: [Point]
    var id: Double { percentile }
}

/// One measurement as plotted on a chart.
struct GrowthPoint: Identifiable, Hashable {
    let id: String
    var date: Date
    var x: Double
    var y: Double
    /// Where it sits on this data set's curves, 0–100, as worked out by the portal.
    var percentile: Double?
}

/// Demo-mode input: one visit's measurements, turned into charts by the mock.
struct GrowthMeasurement: Identifiable, Hashable {
    let id: String
    var date: Date
    /// Age in months at the time of measurement, to one decimal place.
    var ageMonths: Double
    var heightCm: Double
    var weightKg: Double

    var bmi: Double { weightKg / pow(heightCm / 100, 2) }
}

// MARK: - Messaging

/// Someone on the patient's care team who can be messaged.
struct CareTeamMember: Identifiable, Hashable {
    let id: String
    var name: String
    var role: String
    var department: String

    var initials: String {
        name.split(separator: " ").prefix(2).compactMap(\.first).map(String.init).joined()
    }
}

/// A single message within a conversation thread.
struct ConversationMessage: Identifiable, Hashable {
    let id: String
    var authorName: String
    var authorRole: String?
    /// True when written by the account holder rather than the care team.
    var isFromMe: Bool
    var date: Date
    var body: String
    var attachmentNames: [String] = []
}

/// The Messages page's folders. Raw values are the portal's `tag` in
/// GetConversationList (captured from each folder).
nonisolated enum MessageFolder: Int, CaseIterable, Identifiable, Hashable, Sendable {
    case inbox = 1
    case bookmarked = 3
    case trash = 2

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .inbox: "Inbox"
        case .bookmarked: "Bookmarked"
        case .trash: "Archived"
        }
    }

    var systemImage: String {
        switch self {
        case .inbox: "tray"
        case .bookmarked: "bookmark"
        case .trash: "archivebox"
        }
    }
}

/// A file uploaded for a reply, before it's sent.
struct MessageAttachment: Identifiable, Hashable, Sendable {
    /// The portal's `DocumentId`, sent in the reply's `documentIds`.
    let id: String
    var name: String
}

/// A message thread with one or more members of the care team.
struct Conversation: Identifiable, Hashable {
    let id: String
    var subject: String
    var participants: [CareTeamMember]
    var messages: [ConversationMessage]
    var isUnread: Bool
    var isBookmarked: Bool = false
    /// When staff last opened the thread, shown at the end of the transcript.
    var lastViewedByStaff: Date? = nil
    /// The signed-in family member's `wprId`, which a reply is sent as.
    var replyViewerID: String? = nil
    /// From the details' `replyFlags.canReply`; staff can close a thread.
    var canReply: Bool = true

    var lastMessage: ConversationMessage? { messages.last }
    var date: Date { lastMessage?.date ?? .distantPast }
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
    /// The vaccine record this dose belongs to, for fetching its details.
    var vaccineID: String? = nil
}

/// One dose's details from the portal. Any field may be missing; the
/// portal often records only the date and product.
struct ImmunisationDose: Identifiable, Hashable {
    var date: Date
    var productName: String?
    var dose: String?
    var route: String?
    var site: String?
    var location: String?
    var manufacturer: String?
    var lotNumber: String?

    var id: Date { date }
}
