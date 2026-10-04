import Foundation

/// Everything the UI needs from a backend, expressed independently of *how*
/// the data is fetched. `MockPortalService` drives the app today; an
/// `EpicFHIRService` (SMART on FHIR / OAuth2) can conform later without any
/// change to the views.
protocol PortalService: Sendable {
    /// Authenticate and return the resulting profile. Throws on failure.
    func signIn(username: String, password: String) async throws -> PatientProfile

    /// The hospital's medical record number (MRN) for the patient, if known.
    /// The patient's full name and UR (unit record) number.
    func recordHeader(for patientID: String) async throws -> RecordHeader

    func appointments(for patientID: String) async throws -> [Appointment]
    /// The documents available for a past visit (care-team notes, After
    /// Visit Summary), identified by the appointment's id.
    func visitDocuments(appointmentID: String, for patientID: String) async throws -> [VisitDocument]
    /// A past visit's document as a complete, self-contained HTML page.
    func visitDocumentHTML(_ document: VisitDocument, for patientID: String) async throws -> String
    /// Letters shared with the family, newest first.
    func letters(for patientID: String) async throws -> [Letter]
    /// A letter as a complete, self-contained HTML page.
    func letterHTML(_ letter: Letter, for patientID: String) async throws -> String
    /// Referrals on the record, newest first.
    func referrals(for patientID: String) async throws -> [Referral]
    func testResults(for patientID: String) async throws -> [TestResult]
    /// Fills in a result's values, ranges and report, which the list omits.
    func testResultDetails(_ result: TestResult, for patientID: String) async throws -> TestResult
    /// Downloads a scan or report attached to a result (PDF or image bytes).
    func documentData(_ document: ResultDocument, for patientID: String) async throws -> Data
    func medications(for patientID: String) async throws -> [Medication]
    /// Medicines matching `text`, for adding one the hospital hasn't.
    func searchMedications(_ text: String, for patientID: String) async throws -> [MedicationSearchResult]
    /// Adds a medication the family reports taking, from `startDate`. The
    /// care team reviews it at the next visit.
    func addMedication(named name: String, startDate: Date, for patientID: String) async throws
    /// Removes a medication the family added (`isPatientReported`).
    func removeMedication(_ medication: Medication, for patientID: String) async throws
    func messages(for patientID: String) async throws -> [Message]

    /// Message threads with the care team, in one of the Messages folders.
    func conversations(in folder: MessageFolder, for patientID: String) async throws -> [Conversation]
    /// One thread in full, fetched when it's opened.
    func conversation(id: String, for patientID: String) async throws -> Conversation
    // These take several conversations, for selecting more than one in the list.
    /// Adds or removes bookmarks.
    func setConversationsBookmarked(_ isBookmarked: Bool, ids: [String], for patientID: String) async throws
    /// Marks threads read or unread.
    func setConversationsUnread(_ isUnread: Bool, ids: [String], for patientID: String) async throws
    /// Moves threads out of the inbox into the portal's Trash folder.
    func moveConversationsToTrash(ids: [String], for patientID: String) async throws
    /// Puts threads in Trash back in the inbox.
    func restoreConversationsFromTrash(ids: [String], for patientID: String) async throws
    /// Sends a reply to the care team. `includeOtherViewers` copies in
    /// everyone else with access to the record.
    func sendReply(_ text: String, attachments: [MessageAttachment], in conversation: Conversation,
                   includeOtherViewers: Bool, for patientID: String) async throws
    /// Uploads a photo or file to attach to a reply.
    func uploadAttachment(_ data: Data, fileName: String, mimeType: String,
                          for patientID: String) async throws -> MessageAttachment
    /// People who can be messaged about this patient.
    func careTeam(for patientID: String) async throws -> [CareTeamMember]

    /// Growth reference sets (e.g. WHO, CDC), each with its charts, curves
    /// and the child's measurements. The first is the portal's default.
    func growthCharts(for patientID: String) async throws -> [GrowthDataset]

    func healthIssues(for patientID: String) async throws -> [HealthIssue]
    func allergies(for patientID: String) async throws -> [Allergy]
    /// False while a backend can't read allergies yet, so screens say so
    /// rather than showing its empty list as "no known allergies".
    var readsAllergies: Bool { get }
    func immunisations(for patientID: String) async throws -> [Immunisation]
    /// Hospital announcements and links for the bottom of Home.
    func exploreMore(for patientID: String) async throws -> ExploreMoreFeed
    /// The health goal shared with the care team. The portal holds one
    /// free-text goal; the list has at most one entry.
    func patientGoals(for patientID: String) async throws -> [PortalGoal]
    /// Sets the shared goal, replacing any that's there.
    func setPatientGoal(_ text: String, for patientID: String) async throws
    /// Adds an upcoming visit to the portal's wait list for earlier times,
    /// or takes it off.
    func setEarlierVisitAlerts(_ isOn: Bool, appointmentID: String, for patientID: String) async throws
    /// Reasons and the details needed to look up new times for a visit.
    func rescheduleOptions(appointmentID: String, for patientID: String) async throws -> RescheduleOptions
    /// Free times from `startDay` (an Epic day number; nil for today).
    func rescheduleSlots(_ options: RescheduleOptions, appointmentID: String, startDay: Int?,
                         for patientID: String) async throws -> AppointmentSlotPage
    /// False until the portal's booking step has been mapped.
    var booksReschedules: Bool { get }
    /// Moves the visit to the chosen time.
    func reschedule(appointmentID: String, to slot: AppointmentSlot, reason: RescheduleOptions.Reason?,
                    options: RescheduleOptions, for patientID: String) async throws
    /// Per-dose details (product, site, batch…) for one vaccine record.
    func immunisationDoses(vaccineID: String, for patientID: String) async throws -> [ImmunisationDose]
    /// Email, phone numbers and address from the Personal Information page.
    func personalInformation(for patientID: String) async throws -> PersonalInformation
    /// Saves the editable contact details and answers the portal's updated copy.
    func updateContactInformation(_ update: ContactInformationUpdate,
                                  for patientID: String) async throws -> PersonalInformation
    /// Password, two-step verification and device settings from Account Settings.
    func securitySettings(for patientID: String) async throws -> SecuritySettings
    /// Turns the portal's preview features on or off.
    func setPreviewFeatures(_ isOn: Bool, for patientID: String) async throws
    /// Turns "Remember logged-in devices" on or off.
    func setRemembersDevices(_ isOn: Bool, for patientID: String) async throws
    /// Sets a linked account's nickname, colour (an index into
    /// `Theme.accountColours`) and, when given, a new JPEG photo, as the
    /// portal's Family Access page does. An empty nickname goes back to the
    /// patient's own name. Answers the updated accounts.
    func customiseAccount(_ accountID: String, nickname: String, colour: Int,
                          photo: Data?) async throws -> [LinkedAccount]
    /// Each linked account's photo, by account ID, for those that have one.
    func accountPhotos() async -> [String: Data]
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

extension PortalService {
    var readsAllergies: Bool { true }
    var booksReschedules: Bool { false }

    /// The inbox, for the dashboard and notifications.
    func conversations(for patientID: String) async throws -> [Conversation] {
        try await conversations(in: .inbox, for: patientID)
    }
}
