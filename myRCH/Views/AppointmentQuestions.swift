import SwiftUI

enum AppointmentQuestions {
    static let instructions = """
        You are helping a parent prepare questions for their child's \
        upcoming hospital appointment. Suggest clear, short questions a \
        parent could ask the doctor, based only on the information given, \
        such as recent results outside the normal range, new letters or \
        current medicines. Write each as the parent would ask it. Don't \
        answer the questions.
        """

    /// Most visits leave time for a handful of questions.
    static let maxSuggestions = 5

    static func prompt(for appointment: Appointment, session: Session) async -> String {
        let child = await ChildContext.load(session, at: appointment.date)
        let recent = RecordContext.past(months: 6)
        async let results = RecordContext.results(session, in: recent)
        async let letters = RecordContext.letters(session, in: recent)
        async let medications = RecordContext.activeMedications(session)

        var lines = ["Appointment: \(appointment.title), \(appointment.department), \(appointment.date.mediumDate)"]
        if let provider = appointment.provider { lines.append("With: \(provider)") }
        if let age = child.ageLine("Child's age at the visit") { lines.append(age) }
        if !child.conditions.isEmpty { lines.append("Child's recorded conditions: \(child.conditionNames)") }
        lines += RecordContext.block("Test results in the last six months", await results)
        lines += RecordContext.block("Letters in the last six months", await letters)
        lines += RecordContext.block("Current medicines", await medications)
        lines.append("")
        lines.append("Suggest up to \(maxSuggestions) questions the parent could ask at this appointment, one per line starting with \"- \". Reply with only the list.")
        return lines.joined(separator: "\n")
    }

    /// The model's list as separate questions, without bullets or numbers.
    static func parse(_ text: String) -> [String] {
        text.components(separatedBy: .newlines)
            .map { line in
                line.trimmingCharacters(in: .whitespaces)
                    .replacingOccurrences(of: #"^([-•*]|\d+[.)])\s*"#, with: "", options: .regularExpression)
                    .trimmingCharacters(in: .whitespaces)
            }
            .filter { !$0.isEmpty }
            .prefix(maxSuggestions)
            .map { $0 }
    }
}

/// "Questions to ask" for an upcoming visit: the family's own list, which
/// Apple Intelligence can add suggestions to from the child's recent
/// results, letters and medicines. Ticked off as they're asked.
struct AppointmentQuestionsCard: View {
    let appointment: Appointment
    @Environment(Session.self) private var session

    @State private var newQuestion = ""
    @State private var isSuggesting = false
    @State private var failure: String?
    /// Shows a delete button on each question.
    @State private var isEditing = false
    @FocusState private var isTyping: Bool

    private var store: AppointmentQuestionsStore { .shared }
    private var key: String {
        AppointmentQuestionsStore.key(patientID: session.patientID, appointmentID: appointment.id)
    }

    var body: some View {
        let questions = store.questions(for: key)
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Questions to ask")
                    .font(.title3.bold())
                    .foregroundStyle(Theme.ink)
                Spacer()
                if !questions.isEmpty {
                    Button(isEditing ? "Done" : "Edit") { isEditing.toggle() }
                        .font(.subheadline.weight(.semibold))
                        .tint(Theme.brand)
                }
            }
            VStack(alignment: .leading, spacing: 0) {
                ForEach(questions) { question in
                    row(question)
                    Divider().padding(.leading, 52)
                }
                TextField("Add a question", text: $newQuestion, axis: .vertical)
                    .focused($isTyping)
                    .submitLabel(.done)
                    .onSubmit(addTyped)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                if OnDeviceAI.isSupported {
                    Divider().padding(.leading, 16)
                    suggestButton
                }
            }
            .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: Theme.cardRadius))
            if let failure {
                Label(failure, systemImage: "exclamationmark.bubble")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else if questions.contains(where: \.isSuggested) {
                Text("✨ Suggested by Apple Intelligence on this iPhone. Saved on this iPhone only.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                Text("Saved on this iPhone only. Tick each one off as you ask it.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .animation(.default, value: questions)
        .animation(.default, value: isEditing)
        // Nothing left to edit.
        .onChange(of: questions.isEmpty) { if questions.isEmpty { isEditing = false } }
    }

    /// Tapping ticks a question off; in Edit mode, it deletes it instead.
    private func row(_ question: AppointmentQuestionsStore.Question) -> some View {
        Button {
            if isEditing {
                store.remove(question, from: key)
            } else {
                store.toggleAsked(question, in: key)
            }
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 14) {
                Group {
                    if isEditing {
                        Image(systemName: "minus.circle.fill")
                            .foregroundStyle(.white, Theme.red)
                    } else {
                        Image(systemName: question.isAsked ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(question.isAsked ? Theme.green : Color.secondary)
                    }
                }
                .font(.title3)
                .contentTransition(.symbolEffect(.replace))
                Text(question.text)
                    .font(.subheadline)
                    .foregroundStyle(question.isAsked ? .secondary : .primary)
                    .strikethrough(question.isAsked)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
                if question.isSuggested {
                    Image(systemName: "sparkles")
                        .font(.caption)
                        .foregroundStyle(Theme.brand)
                        .accessibilityLabel("Suggested")
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(question.isAsked && !isEditing ? .isSelected : [])
        .accessibilityHint(isEditing ? "Deletes this question" : "")
        .accessibilityAction(named: "Delete") { store.remove(question, from: key) }
        .contextMenu {
            Button("Delete", systemImage: "trash", role: .destructive) {
                store.remove(question, from: key)
            }
        }
    }

    private var suggestButton: some View {
        Button {
            Task { await suggest() }
        } label: {
            HStack(spacing: 14) {
                if isSuggesting {
                    ProgressView().frame(width: 22)
                } else {
                    Image(systemName: "sparkles").frame(width: 22)
                }
                Text(isSuggesting ? "Thinking of questions…" : "Suggest questions")
                    .font(.subheadline.weight(.semibold))
                Spacer()
            }
            .foregroundStyle(Theme.brand)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(isSuggesting)
    }

    private func addTyped() {
        store.add([newQuestion], suggested: false, to: key)
        newQuestion = ""
    }

    private func suggest() async {
        if let reason = OnDeviceAI.unavailableReason {
            failure = reason
            return
        }
        isSuggesting = true
        failure = nil
        defer { isSuggesting = false }
        do {
            let prompt = await AppointmentQuestions.prompt(for: appointment, session: session)
            let text = try await OnDeviceAI.respond(instructions: AppointmentQuestions.instructions, prompt: prompt)
            let suggestions = AppointmentQuestions.parse(text)
            if suggestions.isEmpty {
                failure = "No suggestions this time. Try again, or add your own."
            } else {
                store.add(suggestions, suggested: true, to: key)
            }
        } catch {
            OnDeviceAI.logFailure("Suggest questions: \(appointment.title)", error)
            failure = "Couldn't suggest questions. Try again, or add your own."
        }
    }
}
