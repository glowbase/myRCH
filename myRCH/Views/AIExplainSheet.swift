import FoundationModels
import SwiftUI

/// Streams an on-device explanation into a card per section, with a
/// reminder that the care team, not the model, is the authority. Each
/// feature supplies its instructions and a brief (source text and the
/// sections to ask for); the sheet handles availability, streaming and
/// failure the same way everywhere.
struct AIExplainSheet: View {
    /// Shown large at the top, e.g. the test or letter name.
    let heading: String
    var navigationTitle = "Explain"
    /// The feature's own rules, added to `OnDeviceAI.baseInstructions`.
    let instructions: String
    /// Gathers what the model needs. Runs once per attempt; throwing shows
    /// the failure state.
    let prepare: () async throws -> AIBrief

    @Environment(\.dismiss) private var dismiss

    private enum Phase {
        case preparing
        case generating
        case done
        case unavailable(String)
        case failed
    }

    @State private var phase: Phase = .preparing
    @State private var sections: [AISection] = []
    /// Each section's text so far, by section id.
    @State private var texts: [String: String] = [:]
    /// Bumped by "Try again" to restart the task.
    @State private var attempt = 0

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text(heading)
                        .font(.system(.title2, design: .rounded).bold())
                        .foregroundStyle(Theme.ink)
                    content
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .task(id: attempt) { await generate() }
    }

    @ViewBuilder
    private var content: some View {
        switch phase {
        case .unavailable(let message):
            ContentUnavailableView("Apple Intelligence unavailable", systemImage: "apple.intelligence",
                                   description: Text(message))
        case .failed:
            ContentUnavailableView {
                Label("Couldn't write an explanation", systemImage: "exclamationmark.bubble")
            } description: {
                Text("The on-device model couldn't explain this. Your care team can talk you through it.")
            } actions: {
                Button("Try again") { attempt += 1 }
            }
        case .preparing:
            ProgressView()
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
        case .generating, .done:
            ForEach(sections) { section in
                AISectionCard(title: section.title, systemImage: section.systemImage,
                              text: texts[section.id], isGenerating: isGenerating)
            }
            AIDisclaimer()
        }
    }

    private var isGenerating: Bool {
        if case .generating = phase { true } else { false }
    }

    private func generate() async {
        if let reason = OnDeviceAI.unavailableReason {
            phase = .unavailable(reason)
            return
        }
        phase = .preparing
        texts = [:]
        do {
            let brief = try await prepare()
            sections = brief.sections
            phase = .generating
            // One conversation, a turn per section: later requests see the
            // source from the first, so it doesn't need repeating.
            let chat = LanguageModelSession(model: OnDeviceAI.model,
                                            instructions: OnDeviceAI.instructions(instructions))
            for (index, section) in brief.sections.enumerated() {
                let request = index == 0 ? brief.context + "\n\n" + section.request : section.request
                for try await snapshot in chat.streamResponse(to: request) {
                    texts[section.id] = snapshot.content.trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }
            phase = .done
        } catch is CancellationError {
            // The sheet closed; nothing to show.
        } catch {
            OnDeviceAI.logFailure("\(navigationTitle): \(heading)", error)
            phase = .failed
        }
    }
}

/// A titled card that shows a placeholder until its text arrives, then the
/// text as it streams in.
struct AISectionCard: View {
    let title: String
    let systemImage: String
    let text: String?
    var isGenerating = true

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: systemImage)
                .font(.headline)
                .foregroundStyle(Theme.brand)
            if let text, !text.isEmpty {
                Text(text)
                    .foregroundStyle(.primary)
                    .textSelection(.enabled)
                    .contentTransition(.opacity)
            } else {
                Text("Placeholder text that stands in for the explanation while it's written.")
                    .redacted(reason: .placeholder)
                    .opacity(isGenerating ? 1 : 0)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: Theme.cardRadius))
        .animation(.default, value: text)
    }
}

/// The footer every AI feature carries.
struct AIDisclaimer: View {
    var body: some View {
        Label("Written by Apple Intelligence on this iPhone. Nothing leaves your device. It can make mistakes and isn't medical advice, so always check with your child's care team.",
              systemImage: "apple.intelligence")
            .font(.footnote)
            .foregroundStyle(.secondary)
    }
}

/// The ✨ toolbar button that opens an explanation, hidden on devices that
/// can't run Apple Intelligence.
struct AIExplainToolbarItem: ToolbarContent {
    var title = "Explain"
    let action: () -> Void

    var body: some ToolbarContent {
        if OnDeviceAI.isSupported {
            ToolbarItem(placement: .topBarTrailing) {
                Button(title, systemImage: "sparkles", action: action)
            }
        }
    }
}
