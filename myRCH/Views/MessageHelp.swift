import FoundationModels
import SwiftUI

enum MessageHelp {
    static let instructions = """
        You are helping a parent write a message to their child's hospital \
        care team. Rewrite the parent's draft so it is clear, polite and \
        easy for a busy clinician to act on: say what the concern is, since \
        when, what they've noticed, and what they're asking for. Keep every \
        fact from the draft and add none: no symptoms, dates, names or \
        medical opinions they didn't write. Write in the first person as the \
        parent, in Australian English, without a subject line, greeting \
        placeholders or sign-off placeholders. Keep it short.
        """

    /// Enough of the thread for a reply to address the right question.
    private static let threadLimit = 1_500

    static func prompt(draft: String, replyingTo conversation: Conversation?, recipient: CareTeamMember?) -> String {
        var lines: [String] = []
        if let conversation {
            lines.append("Conversation subject: \(conversation.subject)")
            if let last = conversation.messages.last(where: { !$0.isFromMe }) {
                lines.append("The care team's last message, from \(last.authorName):")
                lines.append(OnDeviceAI.clip(last.body, to: threadLimit))
            }
            lines.append("")
        }
        if let recipient {
            lines.append("Writing to: \(recipient.name), \(recipient.role), \(recipient.department)")
            lines.append("")
        }
        lines.append("The parent's draft:")
        lines.append(draft)
        lines.append("")
        lines.append("Rewrite the draft as the message to send. Reply with only the message.")
        return lines.joined(separator: "\n")
    }
}

/// "Help me write", shown once there's a draft. Opens a sheet with a
/// clearer version the family can use or ignore.
struct MessageHelpButton: View {
    @Binding var draft: String
    var conversation: Conversation? = nil
    var recipient: CareTeamMember? = nil

    @State private var showsHelp = false

    var body: some View {
        if OnDeviceAI.isSupported, !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            Button("Help me write", systemImage: "sparkles") { showsHelp = true }
                .font(.caption.weight(.semibold))
                .tint(Theme.brand)
                .sheet(isPresented: $showsHelp) {
                    MessageHelpSheet(draft: $draft, conversation: conversation, recipient: recipient)
                }
        }
    }
}

private struct MessageHelpSheet: View {
    @Binding var draft: String
    let conversation: Conversation?
    let recipient: CareTeamMember?
    @Environment(\.dismiss) private var dismiss

    @State private var suggestion = ""
    @State private var isWriting = false
    @State private var failure: String?
    @State private var attempt = 0

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if let failure {
                        ContentUnavailableView {
                            Label("Couldn't help with this message", systemImage: "exclamationmark.bubble")
                        } description: {
                            Text(failure)
                        } actions: {
                            Button("Try again") { attempt += 1 }
                        }
                    } else {
                        AISectionCard(title: "Suggested message", systemImage: "sparkles",
                                      text: suggestion, isGenerating: isWriting)
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Your draft")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Text(draft)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        Text("Check it says what you mean before sending. Apple Intelligence wrote it on this iPhone and can make mistakes. Call 000 in an emergency.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Help Me Write")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Keep Mine") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Use This") {
                        draft = suggestion
                        dismiss()
                    }
                    .disabled(isWriting || suggestion.isEmpty)
                }
                ToolbarItem(placement: .bottomBar) {
                    Button("Try Again", systemImage: "arrow.clockwise") { attempt += 1 }
                        .disabled(isWriting)
                }
            }
        }
        .task(id: attempt) { await write() }
    }

    private func write() async {
        if let reason = OnDeviceAI.unavailableReason {
            failure = reason
            return
        }
        failure = nil
        suggestion = ""
        isWriting = true
        defer { isWriting = false }
        let chat = LanguageModelSession(model: OnDeviceAI.model,
                                        instructions: OnDeviceAI.instructions(MessageHelp.instructions))
        let prompt = MessageHelp.prompt(draft: draft, replyingTo: conversation, recipient: recipient)
        do {
            for try await snapshot in chat.streamResponse(to: prompt) {
                suggestion = snapshot.content.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        } catch is CancellationError {
            // The sheet closed.
        } catch {
            OnDeviceAI.logFailure("Help me write", error)
            failure = "The on-device model couldn't rewrite this message. You can still send your own."
        }
    }
}
