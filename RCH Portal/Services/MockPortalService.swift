import Foundation

/// In-memory backend with realistic sample data mirroring the portal
/// screenshots. Any username/password is accepted so the UI can be explored.
struct MockPortalService: PortalService {

    private func delay() async {
        try? await Task.sleep(for: .milliseconds(600))
    }

    private static func date(_ y: Int, _ m: Int, _ d: Int, _ hour: Int = 9, _ minute: Int = 0) -> Date {
        var c = DateComponents()
        c.year = y; c.month = m; c.day = d; c.hour = hour; c.minute = minute
        return Calendar.current.date(from: c) ?? .now
    }

    func signIn(username: String, password: String) async throws -> PatientProfile {
        await delay()
        guard !username.trimmingCharacters(in: .whitespaces).isEmpty,
              !password.isEmpty else {
            throw PortalError.invalidCredentials
        }
        return PatientProfile(
            id: "patient-sallie",
            fullName: "Sallie Anderson",
            preferredName: "Sallie",
            initials: "S",
            linkedAccounts: [
                LinkedAccount(id: "acct-sallie", name: "Sallie", initials: "S", unreadCount: 1,
                              dateOfBirth: Self.date(2018, 3, 14)),
                LinkedAccount(id: "acct-sal", name: "Sal", initials: "S", unreadCount: 0,
                              dateOfBirth: Self.date(2025, 9, 10))
            ]
        )
    }

    /// A made-up MRN so the dashboard chip shows in demo mode.
    func medicalRecordNumber(for patientID: String) async throws -> String? {
        "10000001"
    }

    func appointments(for patientID: String) async throws -> [Appointment] {
        await delay()
        let rchAddress = "50 Flemington Road, Parkville VIC 3052"
        return [
            Appointment(id: "u1", title: "Nephrology Review",
                        department: "Nephrology Clinic",
                        provider: "Kevin Chang, Consultant",
                        date: Self.date(2026, 10, 2, 10), status: .scheduled,
                        isTelehealth: false, hasVisitSummary: false,
                        durationMinutes: 45, address: rchAddress, phone: "03 9345 5818",
                        checkInLocation: "Specialist Clinics, Desk A1 – Red Desk (Ground floor)",
                        instructions: [
                            "Arrive 15 minutes early to check in",
                            "Bring a urine sample collected that morning",
                            "Bring a list of current medications",
                            "Bring your Medicare card"
                        ]),
            Appointment(id: "u2", title: "Telehealth Check-in",
                        department: "Dermatology Streamline Access Clinic",
                        provider: "Sarah Flynn, Registrar",
                        date: Self.date(2026, 11, 14, 14, 30), status: .scheduled,
                        isTelehealth: true, hasVisitSummary: false,
                        durationMinutes: 20, phone: "03 9345 5522",
                        instructions: [
                            "Find a quiet, well-lit spot with good reception",
                            "Have photos of the affected skin ready to share",
                            "The clinician will call from a private number"
                        ]),
            Appointment(id: "u3", title: "Review",
                        department: "Respiratory Medicine",
                        provider: "Joanne Harrison, Consultant",
                        date: Self.date(2026, 12, 11, 14, 30), status: .scheduled,
                        isTelehealth: false, hasVisitSummary: false,
                        durationMinutes: 75, address: rchAddress, phone: "03 9345 5818",
                        checkInLocation: "Specialist Clinics, Desk A1 – Red Desk (Ground floor)",
                        instructions: [
                            "Lung function testing is included — avoid a heavy meal beforehand",
                            "Bring any inhalers and spacers you use"
                        ]),
            Appointment(id: "a1", title: "Telephone",
                        department: "Dermatology Streamline Access Clinic",
                        provider: "Sarah Flynn, Registrar",
                        date: Self.date(2025, 2, 5, 11), status: .completed,
                        isTelehealth: true, hasVisitSummary: false,
                        durationMinutes: 15, phone: "03 9345 5522"),
            Appointment(id: "a2", title: "Telephone",
                        department: "Banksia Ward", provider: "Jamie",
                        date: Self.date(2024, 12, 13, 15), status: .completed,
                        isTelehealth: true, hasVisitSummary: true,
                        durationMinutes: 20, phone: "03 9345 5111",
                        visitSummary: "Discussed sleep and mood since discharge. Things are improving. Continue current routine and call the ward if concerns return."),
            Appointment(id: "a3", title: "Clinic/Practice Visit",
                        department: "Nephrology Clinic",
                        provider: "Kevin Chang, Consultant",
                        date: Self.date(2024, 12, 3, 9, 30), status: .missed,
                        isTelehealth: false, hasVisitSummary: false,
                        durationMinutes: 30, address: rchAddress, phone: "03 9345 5818",
                        checkInLocation: "Specialist Clinics, Desk A1 – Red Desk (Ground floor)"),
            Appointment(id: "a4", title: "Clinic/Practice Visit",
                        department: "Mental Health Service", provider: "Cathie",
                        date: Self.date(2024, 11, 29, 13), status: .completed,
                        isTelehealth: false, hasVisitSummary: true,
                        durationMinutes: 60, address: rchAddress, phone: "03 9345 6011",
                        checkInLocation: "Mental Health Service, Level 1 reception",
                        visitSummary: "Initial assessment completed. Agreed on fortnightly sessions for the next two months. A care plan has been sent to your GP.")
        ]
    }

    /// Mock results already carry their details.
    func testResultDetails(_ result: TestResult, for patientID: String) async throws -> TestResult {
        result
    }

    /// Mock documents have no file; the viewer draws placeholder pages instead.
    func documentData(_ document: ResultDocument, for patientID: String) async throws -> Data {
        Data()
    }

    func testResults(for patientID: String) async throws -> [TestResult] {
        await delay()
        let rchLab = """
            RCH Laboratory Services
            East Building, Level 4
            The Royal Children's Hospital
            50 Flemington Road, Parkville VIC 3052
            03 9345 4200
            """
        return [
            TestResult(id: "t1", name: "Thyroid Function",
                       date: Self.date(2026, 9, 3, 9), kind: .lab,
                       orderingProvider: "Kevin Chang, Consultant", isUnread: true, summary: nil,
                       components: [
                        ResultComponent(id: "t1a", name: "TSH", value: 5.9, unit: "mIU/L",
                                        normalLow: 0.5, normalHigh: 4.5),
                        ResultComponent(id: "t1b", name: "Free T4", value: 13.2, unit: "pmol/L",
                                        normalLow: 10, normalHigh: 20)
                       ],
                       specimen: "Blood", authorisingClinician: "Joanne Harrison, Consultant",
                       resultDate: Self.date(2026, 9, 4, 15), resultingLab: rchLab),
            TestResult(id: "t2", name: "Vitamin D",
                       date: Self.date(2026, 9, 3, 9), kind: .lab,
                       orderingProvider: "Kevin Chang, Consultant", isUnread: true, summary: nil,
                       components: [
                        ResultComponent(id: "t2a", name: "25-OH Vitamin D", value: 48, unit: "nmol/L",
                                        normalLow: 50, normalHigh: 150)
                       ],
                       specimen: "Blood", authorisingClinician: "Joanne Harrison, Consultant",
                       resultDate: Self.date(2026, 9, 5, 11), resultingLab: rchLab),
            TestResult(id: "t3", name: "Allergy IgE",
                       date: Self.date(2026, 8, 21, 12), kind: .lab,
                       orderingProvider: "Nicola Byrne, Registrar", isUnread: false, summary: nil,
                       components: [
                        ResultComponent(id: "t3a", name: "Total IgE", value: 20.8, unit: "kU/L",
                                        normalLow: 0, normalHigh: 25)
                       ],
                       documents: [ResultDocument(id: "t3d1", title: "Scan 1")],
                       specimen: "Blood", authorisingClinician: "Joanne Harrison, Consultant",
                       resultDate: Self.date(2026, 9, 7, 12), resultingLab: rchLab),
            TestResult(id: "t4", name: "Full Blood Examination",
                       date: Self.date(2026, 8, 21, 12), kind: .lab,
                       orderingProvider: "Nicola Byrne, Registrar", isUnread: false, summary: nil,
                       components: [
                        ResultComponent(id: "t4a", name: "Haemoglobin", value: 128, unit: "g/L",
                                        normalLow: 115, normalHigh: 155),
                        ResultComponent(id: "t4b", name: "White cell count", value: 11.8, unit: "×10⁹/L",
                                        normalLow: 4.5, normalHigh: 11.0),
                        ResultComponent(id: "t4c", name: "Platelets", value: 310, unit: "×10⁹/L",
                                        normalLow: 150, normalHigh: 450)
                       ],
                       specimen: "Blood", authorisingClinician: "Helen Savoia, Consultant",
                       resultDate: Self.date(2026, 8, 21, 17), resultingLab: rchLab),
            TestResult(id: "t5", name: "Iron Studies",
                       date: Self.date(2026, 7, 12, 10), kind: .lab,
                       orderingProvider: "Kevin Chang, Consultant", isUnread: false, summary: nil,
                       components: [
                        ResultComponent(id: "t5a", name: "Ferritin", value: 22, unit: "µg/L",
                                        normalLow: 15, normalHigh: 120),
                        ResultComponent(id: "t5b", name: "Transferrin saturation", value: 18, unit: "%",
                                        normalLow: 15, normalHigh: 45)
                       ],
                       specimen: "Blood", authorisingClinician: "Helen Savoia, Consultant",
                       resultDate: Self.date(2026, 7, 13, 9), resultingLab: rchLab),
            TestResult(id: "t6", name: "XR Chest 2 VW",
                       date: Self.date(2026, 7, 2, 14), kind: .imaging,
                       orderingProvider: "Sarah Flynn, Registrar", isUnread: false,
                       summary: "Lungs are clear. Heart size is normal. No acute cardiopulmonary abnormality.",
                       documents: [ResultDocument(id: "t6d1", title: "Radiology report", pageCount: 2)],
                       authorisingClinician: "Mark Tran, Radiologist",
                       resultDate: Self.date(2026, 7, 2, 18), resultingLab: "RCH Medical Imaging"),
            TestResult(id: "t7", name: "Renal Function",
                       date: Self.date(2026, 6, 15, 8), kind: .lab,
                       orderingProvider: "Kevin Chang, Consultant", isUnread: false, summary: nil,
                       components: [
                        ResultComponent(id: "t7a", name: "Creatinine", value: 52, unit: "µmol/L",
                                        normalLow: 30, normalHigh: 70),
                        ResultComponent(id: "t7b", name: "Urea", value: 4.1, unit: "mmol/L",
                                        normalLow: 2.5, normalHigh: 6.5)
                       ],
                       specimen: "Blood", authorisingClinician: "Helen Savoia, Consultant",
                       resultDate: Self.date(2026, 6, 15, 16), resultingLab: rchLab),
            TestResult(id: "t8", name: "Duodenal Biopsy Disaccharidases",
                       date: Self.date(2026, 5, 2, 11), kind: .pathology,
                       orderingProvider: "Anatomical Pathology", isUnread: false,
                       summary: "Disaccharidase activity within normal limits for age. No evidence of lactase deficiency.",
                       documents: [
                        ResultDocument(id: "t8d1", title: "Pathology report", pageCount: 3),
                        ResultDocument(id: "t8d2", title: "Scan 1")
                       ],
                       specimen: "Tissue — duodenal biopsy",
                       authorisingClinician: "Helen Savoia, Consultant",
                       resultDate: Self.date(2026, 5, 16, 10), resultingLab: rchLab),
            TestResult(id: "t9", name: "Trace Metals",
                       date: Self.date(2025, 8, 15, 9), kind: .lab,
                       orderingProvider: "Kevin Chang, Consultant", isUnread: false, summary: nil,
                       components: [
                        ResultComponent(id: "t9a", name: "Zinc", value: 9.2, unit: "µmol/L",
                                        normalLow: 10, normalHigh: 18)
                       ],
                       specimen: "Blood", authorisingClinician: "Helen Savoia, Consultant",
                       resultDate: Self.date(2025, 8, 20, 12), resultingLab: rchLab)
        ]
    }

    func medications(for patientID: String) async throws -> [Medication] {
        await delay()
        return [
            Medication(id: "m1", name: "Sodium chloride", dose: "6% solution",
                       instructions: "Inhale 3 mL using a nebuliser daily. Mix with 3 mL of distilled water to dilute to 3%.",
                       prescriber: "Respiratory Medicine", isActive: true,
                       commonName: "Hypersal", form: .inhaled,
                       prescribedDate: Self.date(2026, 8, 12), approvedBy: "Hani Gowai, Fellow",
                       quantity: "100 sachets", daySupply: 333),
            Medication(id: "m2", name: "Water for injection", dose: "ampoule",
                       instructions: "Take 3 mL by measure daily. Use to dilute Hypersal for nebulisation as advised by the physiotherapy team.",
                       prescriber: "Respiratory Medicine", isActive: true,
                       form: .liquid,
                       prescribedDate: Self.date(2026, 8, 12), approvedBy: "Hani Gowai, Fellow",
                       quantity: "50 ampoules", daySupply: 166),
            Medication(id: "m3", name: "Amoxicillin–clavulanic acid", dose: "400 mg–57 mg/5 mL",
                       instructions: "Take 152 mg of amoxicillin (1.9 mL) by measure orally TWICE a day.",
                       prescriber: "Respiratory Medicine", isActive: true,
                       commonName: "Augmentin Duo", form: .liquid,
                       prescribedDate: Self.date(2026, 9, 18), approvedBy: "Joanne Harrison, Consultant",
                       quantity: "60 mL", daySupply: 14),
            Medication(id: "m4", name: "Levothyroxine", dose: "50 mcg",
                       instructions: "Take 1 tablet by mouth every morning, 30 minutes before food.",
                       prescriber: "Nephrology Clinic", isActive: true,
                       commonName: "Eutroxsig", form: .tablet,
                       prescribedDate: Self.date(2026, 3, 4), approvedBy: "Kevin Chang, Consultant",
                       quantity: "200 tablets", daySupply: 200, canRequestRepeat: true),
            Medication(id: "m5", name: "Cholecalciferol (Vitamin D3)", dose: "1000 IU",
                       instructions: "Take 1 capsule by mouth daily with food.",
                       prescriber: "General Medicine", isActive: true,
                       form: .capsule, prescribedDate: Self.date(2026, 9, 5),
                       approvedBy: "Kevin Chang, Consultant", quantity: "90 capsules", daySupply: 90,
                       canRequestRepeat: true),
            Medication(id: "m6", name: "Amoxicillin", dose: "250 mg/5 mL",
                       instructions: "5 mL three times a day for 7 days.",
                       prescriber: "Emergency Department", isActive: false,
                       form: .liquid, prescribedDate: Self.date(2025, 6, 2),
                       approvedBy: "Priya Nair, Registrar", quantity: "100 mL", daySupply: 7)
        ]
    }

    /// Flat summaries used by the dashboard and notifications, derived from the
    /// conversation threads so both stay in step.
    func messages(for patientID: String) async throws -> [Message] {
        try await conversations(for: patientID).map { conversation in
            let last = conversation.lastMessage
            return Message(
                id: conversation.id,
                subject: conversation.subject,
                sender: last.map { $0.isFromMe ? "You" : $0.authorName } ?? "",
                preview: last?.body.replacingOccurrences(of: "\n", with: " ") ?? "",
                date: conversation.date,
                isUnread: conversation.isUnread)
        }
    }

    func growthMeasurements(for patientID: String) async throws -> [GrowthMeasurement] {
        await delay()
        return [
            GrowthMeasurement(id: "g1", date: Self.date(2025, 9, 10), ageMonths: 0.0,
                              heightCm: 51.5, weightKg: 3.4),
            GrowthMeasurement(id: "g2", date: Self.date(2025, 10, 8), ageMonths: 0.9,
                              heightCm: 52.8, weightKg: 4.0),
            GrowthMeasurement(id: "g3", date: Self.date(2025, 11, 12), ageMonths: 2.1,
                              heightCm: 55.4, weightKg: 4.9),
            GrowthMeasurement(id: "g4", date: Self.date(2026, 1, 28), ageMonths: 4.6,
                              heightCm: 61.4, weightKg: 6.1),
            GrowthMeasurement(id: "g5", date: Self.date(2026, 3, 27), ageMonths: 6.7,
                              heightCm: 66.0, weightKg: 7.0),
            GrowthMeasurement(id: "g6", date: Self.date(2026, 5, 15), ageMonths: 8.3,
                              heightCm: 66.0, weightKg: 7.4),
            GrowthMeasurement(id: "g7", date: Self.date(2026, 7, 3), ageMonths: 9.9,
                              heightCm: 67.0, weightKg: 7.7),
            GrowthMeasurement(id: "g8", date: Self.date(2026, 8, 12), ageMonths: 11.2,
                              heightCm: 67.5, weightKg: 7.9),
            GrowthMeasurement(id: "g9", date: Self.date(2026, 9, 18), ageMonths: 12.4,
                              heightCm: 70.6, weightKg: 8.3)
        ]
    }

    func careTeam(for patientID: String) async throws -> [CareTeamMember] {
        await delay()
        return Self.careTeamMembers
    }

    private static let careTeamMembers: [CareTeamMember] = [
        CareTeamMember(id: "ct1", name: "Louise Heron", role: "Physiotherapist",
                       department: "Respiratory Medicine"),
        CareTeamMember(id: "ct2", name: "Joanne Harrison", role: "Consultant",
                       department: "Respiratory Medicine"),
        CareTeamMember(id: "ct3", name: "Kevin Chang", role: "Consultant",
                       department: "Nephrology Clinic"),
        CareTeamMember(id: "ct4", name: "Sarah Flynn", role: "Registrar",
                       department: "Dermatology Streamline Access Clinic"),
        CareTeamMember(id: "ct5", name: "Specialist Clinics", role: "Administration",
                       department: "The Royal Children's Hospital")
    ]

    func conversations(for patientID: String) async throws -> [Conversation] {
        await delay()
        let louise = Self.careTeamMembers[0]
        let joanne = Self.careTeamMembers[1]
        let kevin = Self.careTeamMembers[2]
        let admin = Self.careTeamMembers[4]

        return [
            Conversation(
                id: "c1", subject: "Hypersal – 3% tolerance",
                participants: [louise, joanne],
                messages: [
                    ConversationMessage(
                        id: "c1m1", authorName: "Louise Heron", authorRole: "Physiotherapist",
                        isFromMe: false, date: Self.date(2026, 9, 2, 17, 5),
                        body: """
                            Good afternoon,

                            I wanted to check in following our recent appointment where we trialled the 3% hypersal nebuliser. How has Sallie been tolerating this?

                            Many thanks,
                            Louise Heron
                            Physiotherapist
                            """),
                    ConversationMessage(
                        id: "c1m2", authorName: "You", authorRole: nil,
                        isFromMe: true, date: Self.date(2026, 9, 7, 12, 27),
                        body: """
                            Good afternoon Louise,

                            Sorry for the delay. We've been really busy lately moving house, so we've been trying to find a rhythm.

                            She seems to be taking it relatively well. She likes to move her head side to side which makes it a little more difficult. She's recently developed quite a nasty cough so we've upped the nebuliser to twice a day.
                            """)
                ],
                isUnread: false,
                lastViewedByStaff: Self.date(2026, 9, 9, 8, 44)),

            Conversation(
                id: "c2", subject: "Thyroid results follow-up",
                participants: [kevin],
                messages: [
                    ConversationMessage(
                        id: "c2m1", authorName: "Kevin Chang", authorRole: "Consultant",
                        isFromMe: false, date: Self.date(2026, 9, 5, 9, 15),
                        body: """
                            Hello,

                            Sallie's latest thyroid function test shows a slightly raised TSH. I'd like to repeat the blood test in six weeks before making any change to her levothyroxine dose.

                            Please keep giving the current dose each morning. Let me know if she seems more tired than usual.

                            Kind regards,
                            Kevin Chang
                            Consultant Nephrologist
                            """,
                        attachmentNames: ["Thyroid results summary.pdf"])
                ],
                isUnread: true),

            Conversation(
                id: "c3", subject: "Question about nebuliser cleaning",
                participants: [louise],
                messages: [
                    ConversationMessage(
                        id: "c3m1", authorName: "You", authorRole: nil,
                        isFromMe: true, date: Self.date(2026, 8, 14, 19, 40),
                        body: "Hi Louise, how often should we be sterilising the nebuliser cups? We've been doing it daily but wanted to check that's right."),
                    ConversationMessage(
                        id: "c3m2", authorName: "Louise Heron", authorRole: "Physiotherapist",
                        isFromMe: false, date: Self.date(2026, 8, 15, 10, 12),
                        body: """
                            Hi,

                            Daily is perfect. Rinse the cup after each use and sterilise once a day, then let it air dry completely.

                            Louise
                            """)
                ],
                isUnread: false,
                lastViewedByStaff: Self.date(2026, 8, 15, 10, 30)),

            Conversation(
                id: "c4", subject: "Appointment reminder – December review",
                participants: [admin],
                messages: [
                    ConversationMessage(
                        id: "c4m1", authorName: "Specialist Clinics", authorRole: "Administration",
                        isFromMe: false, date: Self.date(2026, 7, 20, 11, 0),
                        body: "This is a reminder that Sallie has a Respiratory Medicine review on Friday 11 December 2026 at 2:30 pm. Please arrive 15 minutes early to check in at Desk A1 – Red Desk.")
                ],
                isUnread: false,
                isBookmarked: true,
                lastViewedByStaff: Self.date(2026, 7, 21, 9, 0))
        ]
    }

    func healthIssues(for patientID: String) async throws -> [HealthIssue] {
        await delay()
        return [
            HealthIssue(id: "h1", name: "Hypothyroidism", notedDate: Self.date(2023, 12, 19)),
            HealthIssue(id: "h2", name: "Chronic kidney disease, stage 2",
                        notedDate: Self.date(2022, 6, 10))
        ]
    }

    func allergies(for patientID: String) async throws -> [Allergy] {
        await delay()
        return [
            Allergy(id: "al1", substance: "Penicillins", reaction: "Hives", severity: "High"),
            Allergy(id: "al2", substance: "Peanut", reaction: "Anaphylaxis", severity: "High")
        ]
    }

    func immunisations(for patientID: String) async throws -> [Immunisation] {
        await delay()
        return [
            Immunisation(id: "i1", name: "Influenza (quadrivalent)", date: Self.date(2026, 6, 22)),
            Immunisation(id: "i2", name: "Influenza (quadrivalent)", date: Self.date(2025, 5, 12)),
            Immunisation(id: "i3", name: "MMR (2nd dose)", date: Self.date(2022, 4, 15)),
            Immunisation(id: "i4", name: "DTPa-IPV booster", date: Self.date(2022, 4, 15))
        ]
    }
}
