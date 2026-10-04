import Foundation

/// Medications added while exploring with sample data.
private actor MockAddedMedications {
    static let shared = MockAddedMedications()
    private(set) var items: [Medication] = []
    func add(_ medication: Medication) { items.append(medication) }
    func remove(id: String) { items.removeAll { $0.id == id } }
}

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
            linkedAccounts: Self.accounts
        )
    }

    private static let accounts = [
        LinkedAccount(id: "acct-sallie", name: "Sallie", initials: "S", unreadCount: 1,
                      dateOfBirth: date(2018, 3, 14), tabColor: 5),
        LinkedAccount(id: "acct-sal", name: "Sal", initials: "S", unreadCount: 0,
                      dateOfBirth: date(2025, 9, 10), tabColor: 0)
    ]

    /// Nothing is kept: the change lasts until the next sign-in.
    func customiseAccount(_ accountID: String, nickname: String, colour: Int,
                          photo: Data?) async throws -> [LinkedAccount] {
        await delay()
        return Self.accounts.map { account in
            guard account.id == accountID else { return account }
            var updated = account
            // As the portal does, an empty nickname goes back to the patient's own name.
            if !nickname.isEmpty { updated.name = nickname }
            updated.initials = String(updated.name.prefix(1)).uppercased()
            updated.tabColor = colour
            return updated
        }
    }

    /// Sample accounts have no photos.
    func accountPhotos() async -> [String: Data] { [:] }

    /// A made-up UR number so the dashboard chip shows in demo mode.
    func recordHeader(for patientID: String) async throws -> RecordHeader {
        RecordHeader(fullName: patientID == "acct-sal" ? "Sal Anderson" : "Sallie Anderson", urNumber: "10000001")
    }

    func personalInformation(for patientID: String) async throws -> PersonalInformation {
        await delay()
        return PersonalInformation(
            email: "parent@example.com",
            phoneNumbers: [
                .init(type: "mobile", number: "0400 000 000"),
                .init(type: "home", number: "03 9000 0000")
            ],
            street: "1 Example Street",
            suburb: "Parkville",
            state: "Victoria",
            postcode: "3052",
            country: "Australia",
            emailNeedsVerification: false,
            mobileNeedsVerification: false
        )
    }

    /// Answers the sample details with the edits applied; nothing is kept.
    func updateContactInformation(_ update: ContactInformationUpdate,
                                  for patientID: String) async throws -> PersonalInformation {
        var information = try await personalInformation(for: patientID)
        information.email = update.email
        information.phoneNumbers = [
            .init(type: "mobile", number: update.mobilePhone),
            .init(type: "home", number: information.phone("home")),
            .init(type: "work", number: update.workPhone)
        ].filter { !$0.number.isEmpty }
        return information
    }

    func securitySettings(for patientID: String) async throws -> SecuritySettings {
        await delay()
        return SecuritySettings(
            passwordLastChanged: "29 Dec, 2025",
            passwordChangeAvailable: true,
            passkeysAvailable: true,
            verifiesByEmailOrText: false,
            verifiesByAuthenticatorApp: true,
            twoStepRequired: true,
            remembersDevices: true,
            rememberDevicesAllowed: true,
            previewFeaturesOn: true,
            deactivateAccountAllowed: true
        )
    }

    /// Nothing is kept; the page shows the change until it reloads.
    func setPreviewFeatures(_ isOn: Bool, for patientID: String) async throws { await delay() }
    func setRemembersDevices(_ isOn: Bool, for patientID: String) async throws { await delay() }

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

    func visitDocuments(appointmentID: String, for patientID: String) async throws -> [VisitDocument] {
        guard appointmentID == "a4" else { return [] }
        await delay()
        return [
            VisitDocument(id: "a4-notes", kind: .careTeamNotes, title: "Progress Notes",
                          author: "Cathie", date: Self.date(2024, 11, 29, 15), reportParameters: [:]),
            VisitDocument(id: "a4-avs", kind: .afterVisitSummary, title: "After Visit Summary",
                          reportParameters: [:])
        ]
    }

    func letters(for patientID: String) async throws -> [Letter] {
        await delay()
        return [
            Letter(id: "l1", csn: "a4", date: Self.date(2026, 9, 22), reason: "Send Notes",
                   author: "Kevin Chang, Consultant", isUnread: true),
            Letter(id: "l2", csn: "a2", date: Self.date(2026, 8, 12), reason: "Parent Absence",
                   author: "Jamie", isUnread: false),
            Letter(id: "l3", csn: "a1", date: Self.date(2026, 7, 10), reason: "Referral Letter",
                   author: "Sarah Flynn, Registrar", isUnread: false)
        ]
    }

    func referrals(for patientID: String) async throws -> [Referral] {
        await delay()
        let rch = "The Royal Children's Hospital"
        let authorised = Referral.Status(code: "1", title: "Authorised")
        let closed = Referral.Status(code: "6", title: "Closed")
        return [
            Referral(id: "r1", number: "10000003", status: authorised, created: Self.date(2026, 7, 3),
                     referredTo: "Kevin Chang, Consultant", referredBy: "Sarah Flynn, Registrar",
                     facility: rch, validFrom: Self.date(2026, 7, 3), validUntil: nil),
            Referral(id: "r2", number: "10000002", status: authorised, created: Self.date(2025, 12, 22),
                     referredTo: "", referredBy: "Sarah Flynn, Registrar",
                     facility: rch, validFrom: Self.date(2026, 8, 12), validUntil: nil),
            Referral(id: "r3", number: "10000001", status: closed, created: Self.date(2025, 10, 14),
                     referredTo: "Sarah Flynn, Registrar", referredBy: "Alex Morgan, GP",
                     facility: rch, validFrom: Self.date(2025, 11, 17), validUntil: Self.date(2026, 2, 17))
        ]
    }

    func letterHTML(_ letter: Letter, for patientID: String) async throws -> String {
        await delay()
        return """
        <!DOCTYPE html><html><head><meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <style>body { font: -apple-system-body; padding: 16px; }</style>
        </head><body>
        <p>\(letter.date.mediumDate)</p>
        <p>Dear Parent/Guardian,</p>
        <p>This is a sample \(letter.title.lowercased()) shown in demo mode.</p>
        <p>Kind regards,<br>\(letter.author ?? "The Royal Children's Hospital")</p>
        </body></html>
        """
    }

    /// Stand-in pages for demo mode, in the same shape as the portal's.
    func visitDocumentHTML(_ document: VisitDocument, for patientID: String) async throws -> String {
        await delay()
        let body = switch document.kind {
        case .afterVisitSummary:
            """
            <h1>After Visit Summary</h1>
            <h2>Today's Visit</h2><p>Mental Health Service, 29 Nov 2024</p>
            <h2>What's Next</h2><p>Fortnightly sessions for the next two months.</p>
            <h2>Your Medication List</h2><p>No changes made at this visit.</p>
            """
        case .careTeamNotes:
            """
            <h1>Progress Notes</h1>
            <p>Initial assessment completed with the family. Agreed on fortnightly sessions.
            A care plan has been sent to the GP.</p>
            """
        }
        return """
        <!DOCTYPE html><html><head><meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <style>body { font: -apple-system-body; padding: 12px; } h1 { font-size: 1.4em; } h2 { font-size: 1.1em; margin-top: 1.4em; }</style>
        </head><body>\(body)</body></html>
        """
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
        // A child with cystic fibrosis (F508del homozygous): routine cough
        // swabs, the fat-soluble vitamin and liver checks CF teams run, lung
        // function, and the newborn-screening sweat test.
        return [
            TestResult(id: "t1", name: "Cough Swab Culture",
                       date: Self.date(2026, 9, 3, 9), kind: .pathology,
                       orderingProvider: "Joanne Harrison, Consultant", isUnread: true,
                       summary: "Light growth of Staphylococcus aureus. No Pseudomonas aeruginosa isolated.",
                       components: [
                        ResultComponent(id: "t1a", name: "Culture", value: nil, unit: "",
                                        normalLow: nil, normalHigh: nil,
                                        valueText: "Organism 1\nStaphylococcus aureus\nColony Count Qualitative: light")
                       ],
                       specimen: "Cough swab", authorisingClinician: "Helen Savoia, Consultant",
                       resultDate: Self.date(2026, 9, 5, 11), resultingLab: rchLab),
            TestResult(id: "t2", name: "Fat-Soluble Vitamins",
                       date: Self.date(2026, 9, 3, 9), kind: .lab,
                       orderingProvider: "Joanne Harrison, Consultant", isUnread: true, summary: nil,
                       components: [
                        ResultComponent(id: "t2a", name: "25-OH Vitamin D", value: 48, unit: "nmol/L",
                                        normalLow: 50, normalHigh: 150),
                        ResultComponent(id: "t2b", name: "Vitamin A (retinol)", value: 1.2, unit: "µmol/L",
                                        normalLow: 0.9, normalHigh: 2.5),
                        ResultComponent(id: "t2c", name: "Vitamin E (alpha-tocopherol)", value: 19, unit: "µmol/L",
                                        normalLow: 11, normalHigh: 38)
                       ],
                       specimen: "Blood", authorisingClinician: "Helen Savoia, Consultant",
                       resultDate: Self.date(2026, 9, 5, 11), resultingLab: rchLab),
            TestResult(id: "t3", name: "Faecal Elastase",
                       date: Self.date(2026, 8, 21, 12), kind: .lab,
                       orderingProvider: "Kevin Chang, Consultant", isUnread: false,
                       summary: "Consistent with pancreatic insufficiency. Continue pancreatic enzymes with all meals and snacks.",
                       components: [
                        ResultComponent(id: "t3a", name: "Faecal elastase", value: 15, unit: "µg/g",
                                        normalLow: 200, normalHigh: nil, valueText: "<15", qualifier: .lessThan)
                       ],
                       specimen: "Faeces", authorisingClinician: "Helen Savoia, Consultant",
                       resultDate: Self.date(2026, 8, 26, 10), resultingLab: rchLab),
            TestResult(id: "t4", name: "Full Blood Examination",
                       date: Self.date(2026, 8, 21, 12), kind: .lab,
                       orderingProvider: "Joanne Harrison, Consultant", isUnread: false, summary: nil,
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
            TestResult(id: "t5", name: "Liver Function",
                       date: Self.date(2026, 8, 21, 12), kind: .lab,
                       orderingProvider: "Kevin Chang, Consultant", isUnread: false, summary: nil,
                       components: [
                        ResultComponent(id: "t5a", name: "ALT", value: 34, unit: "U/L",
                                        normalLow: 5, normalHigh: 30),
                        ResultComponent(id: "t5b", name: "GGT", value: 18, unit: "U/L",
                                        normalLow: 5, normalHigh: 25),
                        ResultComponent(id: "t5c", name: "Albumin", value: 41, unit: "g/L",
                                        normalLow: 35, normalHigh: 50)
                       ],
                       specimen: "Blood", authorisingClinician: "Helen Savoia, Consultant",
                       resultDate: Self.date(2026, 8, 21, 18), resultingLab: rchLab),
            TestResult(id: "t6", name: "Lung Function (Spirometry)",
                       date: Self.date(2026, 7, 2, 10), kind: .lab,
                       orderingProvider: "Joanne Harrison, Consultant", isUnread: false,
                       summary: "Normal spirometry. FEV1 stable compared with last year.",
                       components: [
                        ResultComponent(id: "t6a", name: "FEV1 (% predicted)", value: 92, unit: "%",
                                        normalLow: 80, normalHigh: 120),
                        ResultComponent(id: "t6b", name: "FVC (% predicted)", value: 98, unit: "%",
                                        normalLow: 80, normalHigh: 120)
                       ],
                       authorisingClinician: "Joanne Harrison, Consultant",
                       resultDate: Self.date(2026, 7, 2, 12), resultingLab: "RCH Respiratory Laboratory"),
            TestResult(id: "t7", name: "XR Chest 2 VW",
                       date: Self.date(2026, 7, 2, 14), kind: .imaging,
                       orderingProvider: "Joanne Harrison, Consultant", isUnread: false,
                       summary: "Mild peribronchial thickening in both upper lobes, in keeping with known cystic fibrosis. No consolidation. Unchanged from last year.",
                       documents: [ResultDocument(id: "t7d1", title: "Radiology report", pageCount: 2)],
                       authorisingClinician: "Mark Tran, Radiologist",
                       resultDate: Self.date(2026, 7, 2, 18), resultingLab: "RCH Medical Imaging"),
            TestResult(id: "t8", name: "Iron Studies",
                       date: Self.date(2026, 7, 2, 9), kind: .lab,
                       orderingProvider: "Kevin Chang, Consultant", isUnread: false, summary: nil,
                       components: [
                        ResultComponent(id: "t8a", name: "Ferritin", value: 22, unit: "µg/L",
                                        normalLow: 15, normalHigh: 120),
                        ResultComponent(id: "t8b", name: "Transferrin saturation", value: 18, unit: "%",
                                        normalLow: 15, normalHigh: 45)
                       ],
                       specimen: "Blood", authorisingClinician: "Helen Savoia, Consultant",
                       resultDate: Self.date(2026, 7, 3, 9), resultingLab: rchLab),
            TestResult(id: "t9", name: "Allergy IgE",
                       date: Self.date(2026, 7, 2, 9), kind: .lab,
                       orderingProvider: "Joanne Harrison, Consultant", isUnread: false,
                       summary: "Annual screen for allergic bronchopulmonary aspergillosis (ABPA): no evidence.",
                       components: [
                        ResultComponent(id: "t9a", name: "Total IgE", value: 20.8, unit: "kU/L",
                                        normalLow: 0, normalHigh: 25)
                       ],
                       specimen: "Blood", authorisingClinician: "Helen Savoia, Consultant",
                       resultDate: Self.date(2026, 7, 6, 12), resultingLab: rchLab),
            TestResult(id: "t10", name: "Renal Function",
                       date: Self.date(2026, 6, 1, 8), kind: .lab,
                       orderingProvider: "Joanne Harrison, Consultant", isUnread: false,
                       summary: "Checked after inhaled tobramycin: normal.",
                       components: [
                        ResultComponent(id: "t10a", name: "Creatinine", value: 41, unit: "µmol/L",
                                        normalLow: 25, normalHigh: 60),
                        ResultComponent(id: "t10b", name: "Urea", value: 4.1, unit: "mmol/L",
                                        normalLow: 2.5, normalHigh: 6.5)
                       ],
                       specimen: "Blood", authorisingClinician: "Helen Savoia, Consultant",
                       resultDate: Self.date(2026, 6, 1, 16), resultingLab: rchLab),
            TestResult(id: "t11", name: "Trace Metals",
                       date: Self.date(2025, 8, 15, 9), kind: .lab,
                       orderingProvider: "Kevin Chang, Consultant", isUnread: false, summary: nil,
                       components: [
                        ResultComponent(id: "t11a", name: "Zinc", value: 9.2, unit: "µmol/L",
                                        normalLow: 10, normalHigh: 18)
                       ],
                       specimen: "Blood", authorisingClinician: "Helen Savoia, Consultant",
                       resultDate: Self.date(2025, 8, 20, 12), resultingLab: rchLab),
            TestResult(id: "t12", name: "Sweat Test",
                       date: Self.date(2018, 4, 10, 10), kind: .lab,
                       orderingProvider: "Joanne Harrison, Consultant", isUnread: false,
                       summary: "Sweat chloride in the diagnostic range for cystic fibrosis, following newborn screening.",
                       components: [
                        ResultComponent(id: "t12a", name: "Sweat chloride", value: 102, unit: "mmol/L",
                                        normalLow: nil, normalHigh: 29, rangeText: "<30")
                       ],
                       specimen: "Sweat", authorisingClinician: "Helen Savoia, Consultant",
                       resultDate: Self.date(2018, 4, 10, 15), resultingLab: rchLab)
        ]
    }

    func medications(for patientID: String) async throws -> [Medication] {
        await delay()
        return [
            // sourceName keeps m1 and m2's shared-reminder names from before
            // strength and form were separate fields.
            Medication(id: "m1", name: "Sodium chloride", dose: "6%",
                       instructions: "Inhale 3 mL using a nebuliser daily. Mix with 3 mL of distilled water to dilute to 3%.",
                       prescriber: "Respiratory Medicine", isActive: true,
                       commonName: "Hypersal", form: .inhaled,
                       prescribedDate: Self.date(2026, 8, 12), approvedBy: "Hani Gowai, Fellow",
                       quantity: "100 sachets", daySupply: 333,
                       productForm: "Solution", sourceName: "Sodium chloride 6% solution"),
            Medication(id: "m2", name: "Water for injection", dose: "",
                       instructions: "Take 3 mL by measure daily. Use to dilute Hypersal for nebulisation as advised by the physiotherapy team.",
                       prescriber: "Respiratory Medicine", isActive: true,
                       form: .liquid,
                       prescribedDate: Self.date(2026, 8, 12), approvedBy: "Hani Gowai, Fellow",
                       quantity: "50 ampoules", daySupply: 166,
                       productForm: "Ampoule", sourceName: "Water for injection ampoule"),
            Medication(id: "m3", name: "Amoxicillin–clavulanic acid", dose: "400 mg–57 mg/5 mL",
                       instructions: "Take 152 mg of amoxicillin (1.9 mL) by measure orally TWICE a day.",
                       prescriber: "Respiratory Medicine", isActive: true,
                       commonName: "Augmentin Duo", form: .liquid,
                       prescribedDate: Self.date(2026, 9, 18), approvedBy: "Joanne Harrison, Consultant",
                       quantity: "60 mL", daySupply: 14, productForm: "Oral Liquid"),
            Medication(id: "m4", name: "Levothyroxine", dose: "50 mcg",
                       instructions: "Take 1 tablet by mouth every morning, 30 minutes before food.",
                       prescriber: "Nephrology Clinic", isActive: true,
                       commonName: "Eutroxsig", form: .tablet,
                       prescribedDate: Self.date(2026, 3, 4), approvedBy: "Kevin Chang, Consultant",
                       quantity: "200 tablets", daySupply: 200, canRequestRepeat: true, productForm: "Tablet"),
            Medication(id: "m5", name: "Cholecalciferol (Vitamin D3)", dose: "1000 IU",
                       instructions: "Take 1 capsule by mouth daily with food.",
                       prescriber: "General Medicine", isActive: true,
                       form: .capsule, prescribedDate: Self.date(2026, 9, 5),
                       approvedBy: "Kevin Chang, Consultant", quantity: "90 capsules", daySupply: 90,
                       canRequestRepeat: true, productForm: "Capsule"),
            Medication(id: "m6", name: "Amoxicillin", dose: "250 mg/5 mL",
                       instructions: "5 mL three times a day for 7 days.",
                       prescriber: "Emergency Department", isActive: false,
                       form: .liquid, prescribedDate: Self.date(2025, 6, 2),
                       approvedBy: "Priya Nair, Registrar", quantity: "100 mL", daySupply: 7,
                       productForm: "Oral Liquid")
        ] + (await MockAddedMedications.shared.items)
    }

    func searchMedications(_ text: String, for patientID: String) async throws -> [MedicationSearchResult] {
        await delay()
        let names = ["Zinc Sulfate", "Zinc Oxide", "Paracetamol", "Ibuprofen", "Cetirizine",
                     "Loratadine", "Melatonin", "Macrogol 3350", "Probiotic", "Multivitamin"]
        return names.filter { $0.localizedStandardContains(text) }
            .map { MedicationSearchResult(id: "search-\($0)", name: $0) }
    }

    /// Kept in memory until relaunch, so added medications show in the list.
    func addMedication(named name: String, startDate: Date, for patientID: String) async throws {
        await delay()
        let parts = Medication.splitReportedName(name)
        await MockAddedMedications.shared.add(Medication(
            id: "added-\(UUID().uuidString)", name: parts.name, dose: parts.strength ?? "",
            instructions: "", prescriber: "", isActive: true,
            form: MyChartWebService.medicationForm(name: name, sig: nil),
            prescribedDate: startDate, isPatientReported: true, productForm: parts.form, sourceName: name))
    }

    func removeMedication(_ medication: Medication, for patientID: String) async throws {
        await delay()
        await MockAddedMedications.shared.remove(id: medication.id)
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

    /// The demo measurements, charted against the app's approximate sample
    /// curves, in the same shape the portal sends.
    func growthCharts(for patientID: String) async throws -> [GrowthDataset] {
        await delay()
        return GrowthDataSet.all.map { $0.sampleCharts(for: Self.sampleGrowth) }
    }

    private static let sampleGrowth: [GrowthMeasurement] = [
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

    func conversation(id: String, for patientID: String) async throws -> Conversation {
        guard let conversation = try await conversations(for: patientID).first(where: { $0.id == id }) else {
            throw PortalError.network
        }
        return conversation
    }

    /// Demo data isn't stored anywhere, so these only update the screen.
    func setConversationsBookmarked(_ isBookmarked: Bool, ids: [String], for patientID: String) async throws { await delay() }
    func setConversationsUnread(_ isUnread: Bool, ids: [String], for patientID: String) async throws { await delay() }
    func moveConversationsToTrash(ids: [String], for patientID: String) async throws { await delay() }
    func restoreConversationsFromTrash(ids: [String], for patientID: String) async throws { await delay() }
    func sendReply(_ text: String, attachments: [MessageAttachment], in conversation: Conversation,
                   includeOtherViewers: Bool, for patientID: String) async throws { await delay() }
    func uploadAttachment(_ data: Data, fileName: String, mimeType: String,
                          for patientID: String) async throws -> MessageAttachment {
        await delay()
        return MessageAttachment(id: UUID().uuidString, name: fileName)
    }

    /// Demo data doesn't remember changes, so Trash starts empty and
    /// Bookmarked holds the sample that's bookmarked.
    func conversations(in folder: MessageFolder, for patientID: String) async throws -> [Conversation] {
        let all = try await sampleConversations()
        switch folder {
        case .inbox: return all
        case .bookmarked: return all.filter(\.isBookmarked)
        case .trash: return []
        }
    }

    private func sampleConversations() async throws -> [Conversation] {
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

    /// The portal's real Explore More cards: public hospital links.
    /// Demo mode keeps goals on the device only, so the portal list is empty.
    func patientGoals(for patientID: String) async throws -> [PortalGoal] { [] }
    func setPatientGoal(_ text: String, for patientID: String) async throws { await delay() }
    func setEarlierVisitAlerts(_ isOn: Bool, appointmentID: String, for patientID: String) async throws { await delay() }

    /// The portal's reschedule reasons, as RCH words them.
    func rescheduleOptions(appointmentID: String, for patientID: String) async throws -> RescheduleOptions {
        await delay()
        let reasons = ["No Longer Need Service", "Patient/Child Unwell", "Time Unsuitable", "Other"]
        return RescheduleOptions(reasons: reasons.enumerated().map { .init(id: "\($0.offset + 41)", title: $0.element) },
                                 requiresReason: true, lastDay: EpicDay.number(for: .now) + 90,
                                 rescheduleDat: appointmentID)
    }

    /// A few weekday times each week, a week per search, for 90 days.
    func rescheduleSlots(_ options: RescheduleOptions, appointmentID: String, startDay: Int?,
                         for patientID: String) async throws -> AppointmentSlotPage {
        await delay()
        let today = EpicDay.number(for: .now)
        let start = startDay ?? today + 3
        let calendar = Calendar.current
        let slots = (start..<start + 7).flatMap { day -> [AppointmentSlot] in
            guard let date = calendar.date(byAdding: .day, value: day - today, to: calendar.startOfDay(for: .now)),
                  !calendar.isDateInWeekend(date), day % 3 != 0 else { return [] }
            return [(9, 30), (13, 0)].compactMap { hour, minute in
                calendar.date(bySettingHour: hour, minute: minute, second: 0, of: date)
                    .map { AppointmentSlot(id: "mock-\(day)-\(hour)", date: $0, lengthMinutes: 30) }
            }
        }
        let next = start + 7
        return AppointmentSlotPage(slots: slots, nextStartDay: next <= options.lastDay ? next : nil)
    }

    var booksReschedules: Bool { true }

    func reschedule(appointmentID: String, to slot: AppointmentSlot, reason: RescheduleOptions.Reason?,
                    options: RescheduleOptions, for patientID: String) async throws { await delay() }

    func exploreMore(for patientID: String) async throws -> ExploreMoreFeed {
        func link(_ title: String, _ url: String) -> (title: String, url: URL)? {
            URL(string: url).map { (title, $0) }
        }
        return ExploreMoreFeed(title: "Explore More for You", items: [
            ExploreItem(id: "support", title: "Support Us",
                        body: "There are many ways you can support Great Care at The Royal Children's Hospital. Please visit our website to find out more.",
                        primary: link("Take me there", "https://www.rchfoundation.org.au/")),
            ExploreItem(id: "kidsinfo", title: "Kids Health Info",
                        body: "Check out our Kids Health Info resources to learn more about a wide range of health topics and medical conditions.",
                        primary: link("Take me there", "https://www.rch.org.au/kidsinfo/")),
            ExploreItem(id: "telehealth", title: "RCH Telehealth",
                        body: "Do you have a telehealth video call appointment? Click the Telehealth Appointment button to find out more.",
                        primary: link("Telehealth Appointment", "https://www.rch.org.au/telehealth/"))
        ])
    }

    func immunisations(for patientID: String) async throws -> [Immunisation] {
        await delay()
        return [
            Immunisation(id: "i1", name: "Influenza (quadrivalent)", date: Self.date(2026, 6, 22), vaccineID: "v-flu"),
            Immunisation(id: "i2", name: "Influenza (quadrivalent)", date: Self.date(2025, 5, 12), vaccineID: "v-flu"),
            Immunisation(id: "i3", name: "MMR (2nd dose)", date: Self.date(2022, 4, 15), vaccineID: "v-mmr"),
            Immunisation(id: "i4", name: "DTPa-IPV booster", date: Self.date(2022, 4, 15), vaccineID: "v-dtpa")
        ]
    }

    func immunisationDoses(vaccineID: String, for patientID: String) async throws -> [ImmunisationDose] {
        await delay()
        switch vaccineID {
        case "v-flu":
            return [
                ImmunisationDose(date: Self.date(2026, 6, 22), productName: "Vaxigrip Tetra", dose: "0.5 mL",
                                 route: "Intramuscular", site: "Left deltoid", location: "Immunisation Service"),
                ImmunisationDose(date: Self.date(2025, 5, 12), productName: "Vaxigrip Tetra")
            ]
        case "v-mmr":
            return [ImmunisationDose(date: Self.date(2022, 4, 15), productName: "Priorix", route: "Subcutaneous")]
        default:
            return [ImmunisationDose(date: Self.date(2022, 4, 15), productName: "Infanrix IPV")]
        }
    }
}
