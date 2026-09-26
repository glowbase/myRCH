import Foundation

// MARK: - Real backend (stub / integration point)
//
// The "My RCH Portal" app is an Epic MyChart deployment. There is no public
// API for the consumer MyChart endpoints, and automating logins against them
// violates Epic's terms. The sanctioned path for a third-party client is
// SMART on FHIR: an OAuth2 authorization-code + PKCE flow against the hospital's
// FHIR R4 server, which returns a bearer token used for Patient / Appointment /
// Observation / MedicationRequest / Communication reads.
//
// To make this service live you need, from RCH / Epic:
//   • a registered client (client ID, redirect URI, requested scopes)
//   • the FHIR base URL and OAuth authorize/token endpoints
//     (normally discovered via `<base>/.well-known/smart-configuration`)
//
// Until that registration exists, `Session` uses `MockPortalService`. The
// method bodies below intentionally throw so the wiring is obvious.

struct EpicFHIRConfig {
    /// e.g. https://.../api/FHIR/R4/
    var fhirBaseURL: URL
    var authorizeURL: URL
    var tokenURL: URL
    var clientID: String
    var redirectURI: URL
    var scopes: [String]
}

/// Skeleton conformance for a real SMART on FHIR backend. Fill in the OAuth
/// flow (ASWebAuthenticationSession + PKCE) and FHIR resource mapping.
struct EpicFHIRService: PortalService {
    let config: EpicFHIRConfig
    /// Bearer token obtained from the OAuth token exchange.
    var accessToken: String?

    private func notImplemented() throws -> Never {
        throw PortalError.network
    }

    func signIn(username: String, password: String) async throws -> PatientProfile {
        // Real flow: launch ASWebAuthenticationSession against `authorizeURL`
        // with PKCE, exchange the returned code at `tokenURL`, then read the
        // Patient resource. Username/password are handled by Epic's web login,
        // never by this app directly.
        try notImplemented()
    }

    func medicalRecordNumber(for patientID: String) async throws -> String? { try notImplemented() }
    func appointments(for patientID: String) async throws -> [Appointment] { try notImplemented() }
    func testResults(for patientID: String) async throws -> [TestResult] { try notImplemented() }
    func testResultDetails(_ result: TestResult, for patientID: String) async throws -> TestResult { try notImplemented() }
    func documentData(_ document: ResultDocument, for patientID: String) async throws -> Data { try notImplemented() }
    func medications(for patientID: String) async throws -> [Medication] { try notImplemented() }
    func messages(for patientID: String) async throws -> [Message] { try notImplemented() }
    func conversations(for patientID: String) async throws -> [Conversation] { try notImplemented() }
    func careTeam(for patientID: String) async throws -> [CareTeamMember] { try notImplemented() }
    func growthMeasurements(for patientID: String) async throws -> [GrowthMeasurement] { try notImplemented() }
    func healthIssues(for patientID: String) async throws -> [HealthIssue] { try notImplemented() }
    func allergies(for patientID: String) async throws -> [Allergy] { try notImplemented() }
    func immunisations(for patientID: String) async throws -> [Immunisation] { try notImplemented() }
}
