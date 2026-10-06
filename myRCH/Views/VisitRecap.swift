import SwiftUI

enum VisitRecap {
    static let instructions = """
        You are recapping a child's past hospital visit for their parent, \
        from the visit's notes and what followed it: results, letters and \
        medicines. Only report what the information says; if something \
        isn't mentioned, don't guess.
        """

    /// Tests, letters and prescriptions from a visit can take a few weeks
    /// to arrive.
    private static let followUpDays = 21
    /// Shared between the visit's documents, to fit the context window.
    private static let documentsLimit = 5_000

    static func brief(for appointment: Appointment, documents: [VisitDocument], session: Session) async -> AIBrief {
        let start = Calendar.current.startOfDay(for: appointment.date)
        let end = Calendar.current.date(byAdding: .day, value: followUpDays, to: start) ?? appointment.date
        let window = DateInterval(start: start, end: max(start, min(end, .now)))

        let child = await ChildContext.load(session, at: appointment.date)
        async let results = RecordContext.results(session, in: window)
        async let letters = RecordContext.letters(session, in: window)
        async let medications = medicationsStarted(session, in: window)
        async let notes = documentText(documents, session: session)

        var lines = ["Visit: \(appointment.title), \(appointment.department), \(appointment.date.mediumDate)"]
        if let provider = appointment.provider { lines.append("With: \(provider)") }
        if let age = child.ageLine("Child's age at the visit") { lines.append(age) }
        let documentText = await notes
        if !documentText.isEmpty {
            lines += ["", "Notes from the visit:", documentText]
        } else if let summary = appointment.visitSummary {
            lines += ["", "After Visit Summary:", OnDeviceAI.clip(summary, to: documentsLimit)]
        }
        lines += RecordContext.block("Test results collected at or after the visit", await results)
        lines += RecordContext.block("Letters after the visit", await letters)
        lines += RecordContext.block("Medicines started around the visit", await medications)

        return AIBrief(context: lines.joined(separator: "\n"), sections: [
            AISection(title: "What happened", systemImage: "stethoscope",
                      request: "In two to four short sentences, summarise what happened at this visit and what was discussed. If there are no notes, say the visit's notes aren't available in the app. Reply with only the summary."),
            AISection(title: "What changed", systemImage: "arrow.triangle.2.circlepath",
                      request: "Now, in two to four short sentences, describe what changed after the visit: new test results, letters and medicines. If nothing is listed, say so in one sentence. Reply with only the description."),
            AISection(title: "What happens next", systemImage: "arrow.forward.circle",
                      request: "Now list any next steps the notes mention, such as follow-up appointments, tests or things to watch for, one per line starting with \"- \". If none are mentioned, say so in one sentence. Reply with only the list."),
        ])
    }

    /// The visit's notes and After Visit Summary as plain text, sharing the
    /// length limit between them.
    private static func documentText(_ documents: [VisitDocument], session: Session) async -> String {
        guard !documents.isEmpty else { return "" }
        let share = documentsLimit / documents.count
        var parts: [String] = []
        for document in documents {
            guard let html = try? await session.service.visitDocumentHTML(document, for: session.patientID) else { continue }
            let text = MyChartWebService.plainText(fromHTML: html)
            parts.append("\(document.title):\n\(OnDeviceAI.clip(text, to: share))")
        }
        return parts.joined(separator: "\n\n")
    }

    private static func medicationsStarted(_ session: Session, in window: DateInterval) async -> [String] {
        let all = (try? await session.service.medications(for: session.patientID)) ?? []
        return all.filter { $0.prescribedDate.map(window.contains) ?? false }
            .map { "- \($0.reminderName)" + ($0.prescribedDate.map { ", from \($0.mediumDate)" } ?? "") }
    }
}

/// Recaps a past visit on device.
struct VisitRecapSheet: View {
    let appointment: Appointment
    let documents: [VisitDocument]
    @Environment(Session.self) private var session

    var body: some View {
        AIExplainSheet(heading: appointment.title, navigationTitle: "Visit Recap",
                       instructions: VisitRecap.instructions) {
            await VisitRecap.brief(for: appointment, documents: documents, session: session)
        }
    }
}
