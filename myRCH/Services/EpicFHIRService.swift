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

    func recordHeader(for patientID: String) async throws -> RecordHeader { try notImplemented() }
    func appointments(for patientID: String) async throws -> [Appointment] { try notImplemented() }
    func visitDocuments(appointmentID: String, for patientID: String) async throws -> [VisitDocument] { try notImplemented() }
    func letters(for patientID: String) async throws -> [Letter] { try notImplemented() }
    func letterHTML(_ letter: Letter, for patientID: String) async throws -> String { try notImplemented() }
    func visitDocumentHTML(_ document: VisitDocument, for patientID: String) async throws -> String { try notImplemented() }
    func testResults(for patientID: String) async throws -> [TestResult] { try notImplemented() }
    func testResultDetails(_ result: TestResult, for patientID: String) async throws -> TestResult { try notImplemented() }
    func documentData(_ document: ResultDocument, for patientID: String) async throws -> Data { try notImplemented() }
    func medications(for patientID: String) async throws -> [Medication] { try notImplemented() }
    func searchMedications(_ text: String, for patientID: String) async throws -> [MedicationSearchResult] { try notImplemented() }
    func addMedication(named name: String, startDate: Date, for patientID: String) async throws { try notImplemented() }
    func removeMedication(_ medication: Medication, for patientID: String) async throws { try notImplemented() }
    func messages(for patientID: String) async throws -> [Message] { try notImplemented() }
    func conversations(in folder: MessageFolder, for patientID: String) async throws -> [Conversation] { try notImplemented() }
    func conversation(id: String, for patientID: String) async throws -> Conversation { try notImplemented() }
    func setConversationsBookmarked(_ isBookmarked: Bool, ids: [String], for patientID: String) async throws { try notImplemented() }
    func setConversationsUnread(_ isUnread: Bool, ids: [String], for patientID: String) async throws { try notImplemented() }
    func moveConversationsToTrash(ids: [String], for patientID: String) async throws { try notImplemented() }
    func restoreConversationsFromTrash(ids: [String], for patientID: String) async throws { try notImplemented() }
    func sendReply(_ text: String, attachments: [MessageAttachment], in conversation: Conversation,
                   includeOtherViewers: Bool, for patientID: String) async throws { try notImplemented() }
    func uploadAttachment(_ data: Data, fileName: String, mimeType: String,
                          for patientID: String) async throws -> MessageAttachment { try notImplemented() }
    func careTeam(for patientID: String) async throws -> [CareTeamMember] { try notImplemented() }
    func growthCharts(for patientID: String) async throws -> [GrowthDataset] { try notImplemented() }
    func healthIssues(for patientID: String) async throws -> [HealthIssue] { try notImplemented() }
    func allergies(for patientID: String) async throws -> [Allergy] { try notImplemented() }
    func immunisations(for patientID: String) async throws -> [Immunisation] { try notImplemented() }
    func exploreMore(for patientID: String) async throws -> ExploreMoreFeed { try notImplemented() }
    func patientGoals(for patientID: String) async throws -> [PortalGoal] { try notImplemented() }
    func setPatientGoal(_ text: String, for patientID: String) async throws { try notImplemented() }
    func setEarlierVisitAlerts(_ isOn: Bool, appointmentID: String, for patientID: String) async throws { try notImplemented() }
    func rescheduleOptions(appointmentID: String, for patientID: String) async throws -> RescheduleOptions { try notImplemented() }
    func rescheduleSlots(_ options: RescheduleOptions, appointmentID: String, startDay: Int?,
                         for patientID: String) async throws -> AppointmentSlotPage { try notImplemented() }
    func reschedule(appointmentID: String, to slot: AppointmentSlot, reason: RescheduleOptions.Reason?,
                    options: RescheduleOptions, for patientID: String) async throws { try notImplemented() }
    func immunisationDoses(vaccineID: String, for patientID: String) async throws -> [ImmunisationDose] { try notImplemented() }
    func personalInformation(for patientID: String) async throws -> PersonalInformation { try notImplemented() }
    func updateContactInformation(_ update: ContactInformationUpdate,
                                  for patientID: String) async throws -> PersonalInformation { try notImplemented() }
    func securitySettings(for patientID: String) async throws -> SecuritySettings { try notImplemented() }
    func setPreviewFeatures(_ isOn: Bool, for patientID: String) async throws { try notImplemented() }
    func setRemembersDevices(_ isOn: Bool, for patientID: String) async throws { try notImplemented() }
    func passkeys(for patientID: String) async throws -> PasskeyInfo { try notImplemented() }
    func renamePasskey(_ passkeyID: String, to name: String, for patientID: String) async throws -> Passkey { try notImplemented() }
    func removePasskey(_ passkeyID: String, for patientID: String) async throws { try notImplemented() }
    func verifyPassword(_ password: String, for patientID: String) async throws -> PasswordCheck { try notImplemented() }
    func customiseAccount(_ accountID: String, nickname: String, colour: Int,
                          photo: AccountPhotoChange) async throws -> [LinkedAccount] { try notImplemented() }
    func accountPhotos() async -> [String: Data] { [:] }
    func communicationPreferences(for patientID: String) async throws -> CommunicationPreferences { try notImplemented() }
    func updateCommunicationPreferences(_ preferences: CommunicationPreferences,
                                        for patientID: String) async throws { try notImplemented() }
}
