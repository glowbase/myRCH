import Foundation

/// Everything the UI needs from a backend, expressed independently of *how*
/// the data is fetched. `MockPortalService` drives the app today; an
/// `EpicFHIRService` (SMART on FHIR / OAuth2) can conform later without any
/// change to the views.
protocol PortalService: Sendable {
    /// Authenticate and return the resulting profile. Throws on failure.
    func signIn(username: String, password: String) async throws -> PatientProfile

    /// The hospital's medical record number (MRN) for the patient, if known.
    func medicalRecordNumber(for patientID: String) async throws -> String?

    func appointments(for patientID: String) async throws -> [Appointment]
    func testResults(for patientID: String) async throws -> [TestResult]
    /// Fills in a result's values, ranges and report, which the list omits.
    func testResultDetails(_ result: TestResult, for patientID: String) async throws -> TestResult
    /// Downloads a scan or report attached to a result (PDF or image bytes).
    func documentData(_ document: ResultDocument, for patientID: String) async throws -> Data
    func medications(for patientID: String) async throws -> [Medication]
    func messages(for patientID: String) async throws -> [Message]

    /// Message threads with the care team.
    func conversations(for patientID: String) async throws -> [Conversation]
    /// People who can be messaged about this patient.
    func careTeam(for patientID: String) async throws -> [CareTeamMember]

    /// Height/weight measurements for the growth charts, oldest first.
    func growthMeasurements(for patientID: String) async throws -> [GrowthMeasurement]

    func healthIssues(for patientID: String) async throws -> [HealthIssue]
    func allergies(for patientID: String) async throws -> [Allergy]
    func immunisations(for patientID: String) async throws -> [Immunisation]
}

enum PortalError: LocalizedError {
    case invalidCredentials
    case network

    var errorDescription: String? {
        switch self {
        case .invalidCredentials:
            "The username or password you entered is incorrect."
        case .network:
            "We couldn't reach the portal. Please check your connection and try again."
        }
    }
}
