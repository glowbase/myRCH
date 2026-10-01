import FoundationModels
import SwiftUI

/// Look up any medical word or abbreviation and get a plain explanation,
/// written on device. The child's conditions help pick the right meaning
/// of an abbreviation (e.g. "PERT" in cystic fibrosis).
struct MedicalWordsView: View {
    /// Looked up straight away, e.g. from a Browse search.
    var initialTerm: String? = nil
    @Environment(Session.self) private var session

    @State private var term = ""
    @State private var looking: String?
    @State private var explanation: String?
    @State private var isWriting = false
    @State private var failure: String?
    @FocusState private var isTyping: Bool

    /// Words looked up this launch, newest first, to look at again.
    @MainActor private static var recent: [String] = []

    var body: some View {
        List {
            Section {
                HStack {
                    TextField("A word or abbreviation, e.g. FEV1", text: $term)
                        .focused($isTyping)
                        .submitLabel(.search)
                        .autocorrectionDisabled()
                        .onSubmit { lookUp(term) }
                    Button("Explain") { lookUp(term) }
                        .disabled(term.trimmingCharacters(in: .whitespaces).isEmpty || isWriting)
                }
            } footer: {
                Text("Explained by Apple Intelligence on this iPhone. It can make mistakes, so check with your child's care team.")
            }

            if let looking {
                Section(looking) {
                    if let failure {
                        Label(failure, systemImage: "exclamationmark.bubble")
                            .foregroundStyle(.secondary)
                    } else if let explanation, !explanation.isEmpty {
                        Text(explanation)
                            .textSelection(.enabled)
                            .contentTransition(.opacity)
                    } else {
                        Text("Placeholder text that stands in for the explanation while it's written.")
                            .redacted(reason: .placeholder)
                    }
                }
                .animation(.default, value: explanation)
            }

            let recent = Self.recent.filter { $0 != looking }
            if !recent.isEmpty {
                Section("Recent") {
                    ForEach(recent, id: \.self) { word in
                        Button(word) { lookUp(word) }
                            .tint(.primary)
                    }
                }
            }
        }
        .navigationTitle("Medical Words")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: looking) { await explain() }
        .onAppear {
            if let initialTerm, looking == nil {
                term = initialTerm
                lookUp(initialTerm)
            } else if looking == nil {
                isTyping = true
            }
        }
    }

    private func lookUp(_ word: String) {
        let word = word.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !word.isEmpty else { return }
        isTyping = false
        term = word
        Self.recent.removeAll { $0.caseInsensitiveCompare(word) == .orderedSame }
        Self.recent.insert(word, at: 0)
        looking = word
    }

    private static let instructions = """
        You explain one medical word, abbreviation or phrase to a parent. \
        Say what it means in two to four short sentences, then, if it \
        helps, one everyday example. If it's an abbreviation with several \
        meanings, use the one that fits the child's conditions and say \
        what the letters stand for. If you don't know the word, say so \
        rather than guessing.
        """

    private func explain() async {
        guard let looking else { return }
        if let reason = OnDeviceAI.unavailableReason {
            failure = reason
            return
        }
        failure = nil
        explanation = nil
        isWriting = true
        defer { isWriting = false }

        let child = await ChildContext.load(session)
        var lines: [String] = []
        if !child.conditions.isEmpty { lines.append("Child's recorded conditions: \(child.conditionNames)") }
        lines.append("Word to explain: \(looking)")
        lines.append("")
        lines.append("Explain it. Reply with only the explanation.")

        let chat = LanguageModelSession(model: OnDeviceAI.model,
                                        instructions: OnDeviceAI.instructions(Self.instructions))
        do {
            for try await snapshot in chat.streamResponse(to: lines.joined(separator: "\n")) {
                explanation = snapshot.content.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        } catch is CancellationError {
            // Another word was looked up.
        } catch {
            OnDeviceAI.logFailure("Medical words: \(looking)", error)
            failure = "Couldn't explain this word. Try again, or ask the care team."
        }
    }
}

/// The book button in explanation sheets, for looking up a word while
/// reading.
struct MedicalWordsButton: View {
    @State private var showsWords = false

    var body: some View {
        Button("Look Up a Word", systemImage: "character.book.closed") { showsWords = true }
            .sheet(isPresented: $showsWords) {
                NavigationStack {
                    MedicalWordsView()
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button("Done") { showsWords = false }
                            }
                        }
                }
            }
    }
}
