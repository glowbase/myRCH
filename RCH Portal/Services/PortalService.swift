import Foundation

/// Everything the UI needs from a backend, expressed independently of *how*
/// the data is fetched. `MockPortalService` drives the app today; an
/// `EpicFHIRService` (SMART on FHIR / OAuth2) can conform later without any
/// change to the views.
protocol PortalService: Sendable {
    /// Authenticate and return the resulting profile. Throws on failure.
    func signIn(username: String, password: String) async throws -> PatientProfile

    func appointments(for patientID: String) async throws -> [Appointment]
    func testResults(for patientID: String) async throws -> [TestResult]
    func medications(for patientID: String) async throws -> [Medication]
    func messages(for patientID: String) async throws -> [Message]

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
