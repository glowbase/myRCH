import FoundationModels
import OSLog

/// Shared set-up for every Apple Intelligence feature: the model, the
/// house rules all prompts follow, and the child's details that give them
/// context. Everything runs on device; nothing is sent anywhere.
enum OnDeviceAI {
    private static let logger = Logger(subsystem: "com.glowbase.myRCH", category: "OnDeviceAI")

    /// Logs why generation failed, so it shows in Xcode's console. `what`
    /// names the feature and item, e.g. "Explain Result: Zinc".
    static func logFailure(_ what: String, _ error: any Error) {
        logger.error("\(what, privacy: .public) failed: \(String(describing: error), privacy: .public)")
    }

    /// Health records routinely mention infections, organisms and abnormal
    /// findings, which the default guardrails reject. The permissive mode
    /// allows them, but only for plain-text responses, so features ask for
    /// text rather than guided generation.
    static let model = SystemLanguageModel(guardrails: .permissiveContentTransformations)

    /// Whether to offer AI features at all: hidden on devices that can
    /// never run Apple Intelligence, shown otherwise (the sheets explain if
    /// it's switched off or still downloading).
    static var isSupported: Bool {
        model.availability != .unavailable(.deviceNotEligible)
    }

    /// Why the model can't be used right now, for showing to the family, or
    /// nil when it's ready.
    static var unavailableReason: String? {
        switch model.availability {
        case .available:
            nil
        case .unavailable(.appleIntelligenceNotEnabled):
            "Turn on Apple Intelligence in Settings to use this."
        case .unavailable(.modelNotReady):
            "Apple Intelligence is still getting ready on this iPhone. Try again in a little while."
        case .unavailable:
            "This iPhone can't run Apple Intelligence."
        }
    }

    /// Rules every feature shares, ahead of its own task instructions.
    static let baseInstructions = """
        You help parents of children treated at The Royal Children's Hospital \
        Melbourne understand their child's health information. Write in \
        Australian English, in warm, plain language a parent without medical \
        training can follow. Explain medical terms when you use them. Be \
        factual and calm. Never diagnose, never suggest treatment or doses, \
        and never say something is definitely fine or definitely serious. \
        When you describe causes or effects, keep them general, using words \
        like "can" and "sometimes", and say the care team will know what \
        applies to this child. When the child's age is given, keep \
        explanations relevant to a child of that age. Only use the \
        information you are given; don't invent details.
        """

    static func instructions(_ task: String) -> String {
        baseInstructions + "\n\n" + task
    }

    /// Cuts long source text (letters, reports) to fit the model's small
    /// context window, marking the cut so the model knows there's more.
    static func clip(_ text: String, to limit: Int) -> String {
        guard text.count > limit else { return text }
        return String(text.prefix(limit)) + "\n[…the rest is cut short]"
    }

    /// One plain-text answer, for short features that don't stream into a
    /// sheet (e.g. the Home digest).
    static func respond(instructions: String, prompt: String) async throws -> String {
        let session = LanguageModelSession(model: model, instructions: self.instructions(instructions))
        let response = try await session.respond(to: prompt)
        return response.content.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// The child's age and recorded conditions, which make explanations
/// relevant to them, e.g. why zinc matters in cystic fibrosis.
struct ChildContext {
    /// e.g. "8 years", on the date the information is about.
    var age: String?
    var conditions: [HealthIssue]

    /// Enough for any real problem list without crowding the context window.
    private static let conditionLimit = 10

    /// Loads the conditions (cached by the service, so usually instant) and
    /// works out the age on `date`. The account is matched on the record
    /// being viewed, not `activeAccount`, whose fallback could give another
    /// child's age. Missing details are simply left out.
    static func load(_ session: Session, at date: Date = .now) async -> ChildContext {
        let account = session.profile?.linkedAccounts.first { $0.id == session.patientID }
        let conditions = (try? await session.service.healthIssues(for: session.patientID)) ?? []
        return ChildContext(age: account?.dateOfBirth?.ageDescription(at: date),
                            conditions: conditions)
    }

    /// e.g. "Child's age: 8 years", or nil when the age isn't known.
    func ageLine(_ label: String = "Child's age") -> String? {
        age.map { "\(label): \($0)" }
    }

    /// The conditions as one line for a prompt, e.g. "Cystic fibrosis; Asthma".
    var conditionNames: String {
        conditions.prefix(Self.conditionLimit).map(\.name).joined(separator: "; ")
    }

    /// Names the condition when there's only one; the portal's own wording,
    /// since lowercasing would mangle acronyms like "CKD".
    var conditionsTitle: String {
        if conditions.count == 1, let name = conditions.first?.name {
            return "What this means with \(name)"
        }
        return "What this means with your child's conditions"
    }

    /// A last section relating `subject` (e.g. "this result") to the child's
    /// conditions, or nil when none are recorded. Asked last, so the
    /// conditions can't colour the general explanation above it.
    func conditionsSection(about subject: String, example: String) -> AISection? {
        guard !conditions.isEmpty else { return nil }
        return AISection(
            title: conditionsTitle, systemImage: "heart.text.clipboard",
            request: "Now, the child's recorded conditions are: \(conditionNames). In two to four short sentences, explain what \(subject) can mean for a child with the condition or conditions it relates to, \(example). Only mention conditions that genuinely relate; if none do, say in one sentence that \(subject) isn't usually linked to them. Reply with only the explanation.")
    }
}

/// One card in an explanation sheet: its heading and what to ask the model.
struct AISection: Identifiable {
    var title: String
    var systemImage: String
    var request: String
    var id: String { title }
}

/// What an explanation sheet sends the model: the source information, then
/// one request per card, all in a single conversation.
struct AIBrief {
    var context: String
    var sections: [AISection]
}
