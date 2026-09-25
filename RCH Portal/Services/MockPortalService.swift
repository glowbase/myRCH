import Foundation

/// In-memory backend with realistic sample data mirroring the portal
/// screenshots. Any username/password is accepted so the UI can be explored.
struct MockPortalService: PortalService {

    private func delay() async {
        try? await Task.sleep(for: .milliseconds(600))
    }

    private static func date(_ y: Int, _ m: Int, _ d: Int, _ hour: Int = 9) -> Date {
        var c = DateComponents()
        c.year = y; c.month = m; c.day = d; c.hour = hour
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
                LinkedAccount(id: "acct-sallie", name: "Sallie", initials: "S", unreadCount: 1),
                LinkedAccount(id: "acct-sal", name: "Sal", initials: "S", unreadCount: 0)
            ]
        )
    }

    func appointments(for patientID: String) async throws -> [Appointment] {
        await delay()
        return [
            Appointment(id: "u1", title: "Nephrology Review",
                        department: "Nephrology Clinic",
                        provider: "Kevin Chang, Consultant",
                        date: Self.date(2026, 10, 2, 10), status: .scheduled,
                        isTelehealth: false, hasVisitSummary: false),
            Appointment(id: "u2", title: "Telehealth Check-in",
                        department: "Dermatology Streamline Access Clinic",
                        provider: "Sarah Flynn, Registrar",
                        date: Self.date(2026, 11, 14, 14), status: .scheduled,
                        isTelehealth: true, hasVisitSummary: false),
            Appointment(id: "a1", title: "Telephone",
                        department: "Dermatology Streamline Access Clinic",
                        provider: "Sarah Flynn, Registrar",
                        date: Self.date(2025, 2, 5), status: .completed,
                        isTelehealth: true, hasVisitSummary: false),
            Appointment(id: "a2", title: "Telephone",
                        department: "Banksia Ward", provider: "Jamie",
                        date: Self.date(2024, 12, 13), status: .completed,
                        isTelehealth: true, hasVisitSummary: true),
            Appointment(id: "a3", title: "Clinic/Practice Visit",
                        department: "Nephrology Clinic",
                        provider: "Kevin Chang, Consultant",
                        date: Self.date(2024, 12, 3), status: .missed,
                        isTelehealth: false, hasVisitSummary: false),
            Appointment(id: "a4", title: "Clinic/Practice Visit",
                        department: "Mental Health Service", provider: "Cathie",
                        date: Self.date(2024, 11, 29), status: .completed,
                        isTelehealth: false, hasVisitSummary: true)
        ]
    }

    func testResults(for patientID: String) async throws -> [TestResult] {
        await delay()
        return [
            TestResult(id: "t1", name: "Trace Metal (Add On)",
                       date: Self.date(2024, 8, 15), kind: .lab,
                       orderingProvider: "Medipath", isUnread: true, summary: nil),
            TestResult(id: "t2", name: "XR Chest 2 VW",
                       date: Self.date(2024, 2, 17), kind: .imaging,
                       orderingProvider: "Radiology", isUnread: false,
                       summary: "No acute cardiopulmonary abnormality."),
            TestResult(id: "t3", name: "Thyroid Function (Add On)",
                       date: Self.date(2023, 12, 19), kind: .lab,
                       orderingProvider: "Medipath", isUnread: false, summary: nil),
            TestResult(id: "t4", name: "Thyroid Function (Add On)",
                       date: Self.date(2023, 12, 18), kind: .lab,
                       orderingProvider: "Medipath", isUnread: false, summary: nil),
            TestResult(id: "t5", name: "Duodenal Biopsy Disaccharidases",
                       date: Self.date(2023, 11, 2), kind: .pathology,
                       orderingProvider: "Anatomical Pathology", isUnread: false, summary: nil)
        ]
    }

    func medications(for patientID: String) async throws -> [Medication] {
        await delay()
        return [
            Medication(id: "m1", name: "Levothyroxine", dose: "50 mcg",
                       instructions: "Take 1 tablet by mouth every morning",
                       prescriber: "Nephrology Clinic", isActive: true),
            Medication(id: "m2", name: "Cholecalciferol (Vitamin D3)", dose: "1000 IU",
                       instructions: "Take 1 capsule by mouth daily",
                       prescriber: "General Medicine", isActive: true),
            Medication(id: "m3", name: "Amoxicillin", dose: "250 mg/5 mL",
                       instructions: "5 mL three times a day for 7 days",
                       prescriber: "Emergency Department", isActive: false)
        ]
    }

    func messages(for patientID: String) async throws -> [Message] {
        await delay()
        return [
            Message(id: "msg1", subject: "Your recent test results",
                    sender: "Nephrology Clinic",
                    preview: "Your thyroid function results are now available to view…",
                    date: Self.date(2024, 12, 20, 14), isUnread: true),
            Message(id: "msg2", subject: "Appointment reminder",
                    sender: "Dermatology Clinic",
                    preview: "This is a reminder for your upcoming telehealth appointment…",
                    date: Self.date(2024, 12, 1, 11), isUnread: false)
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
            Immunisation(id: "i1", name: "Influenza", date: Self.date(2025, 4, 2)),
            Immunisation(id: "i2", name: "MMR (2nd dose)", date: Self.date(2021, 7, 15)),
            Immunisation(id: "i3", name: "DTPa booster", date: Self.date(2020, 3, 9))
        ]
    }
}
