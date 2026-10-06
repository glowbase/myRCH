import SwiftUI

/// What kind of portal document is being explained, which shapes the
/// prompt: letters are written to other doctors, visit notes record what
/// happened at a visit.
enum ExplainableDocument {
    case letter(Letter)
    case visitDocument(VisitDocument)

    /// For the prompt and the logs, e.g. "Referral Letter".
    var label: String {
        switch self {
        case .letter(let letter): letter.title
        case .visitDocument(let document):
            switch document.kind {
            case .afterVisitSummary: "After Visit Summary"
            case .careTeamNotes: "Care team notes from a visit"
            }
        }
    }

    var date: Date? {
        switch self {
        case .letter(let letter): letter.date
        case .visitDocument(let document): document.date
        }
    }

    var author: String? {
        switch self {
        case .letter(let letter): letter.author
        case .visitDocument(let document): document.author
        }
    }

    var buttonTitle: String {
        switch self {
        case .letter: "Explain Letter"
        case .visitDocument: "Explain Notes"
        }
    }
}

enum DocumentExplainer {
    static let instructions = """
        You are explaining a document from the child's hospital care team. \
        Hospital letters and notes are written for other doctors, so \
        translate them into words a parent understands. Only report what \
        the document says; don't add advice it doesn't contain. If the \
        document mentions results, medicines or plans, describe them as the \
        document does.
        """

    /// Letters run long; this keeps the text, instructions and four answers
    /// within the model's context window.
    private static let textLimit = 6_000

    static func brief(for document: ExplainableDocument, html: String, child: ChildContext) -> AIBrief {
        var lines = ["Document: \(document.label)"]
        if let date = document.date { lines.append("Date: \(date.mediumDate)") }
        if let author = document.author { lines.append("From: \(author)") }
        if let age = child.ageLine("Child's age at the time") { lines.append(age) }
        lines.append("")
        lines.append("Document text:")
        lines.append(OnDeviceAI.clip(MyChartWebService.plainText(fromHTML: html), to: textLimit))

        return AIBrief(context: lines.joined(separator: "\n"), sections: [
            AISection(title: "In short", systemImage: "text.alignleft",
                      request: "In three to five short sentences, summarise what this document says about the child: why it was written and the main points. Reply with only the summary."),
            AISection(title: "What you may need to do", systemImage: "checklist",
                      request: "Now list anything the document asks the family to do, arrange or watch for, such as appointments, tests, medicine changes or warning signs, one per line starting with \"- \". If it asks nothing of the family, say so in one sentence. Reply with only the list."),
            AISection(title: "Words explained", systemImage: "character.book.closed",
                      request: "Now pick up to five medical words or abbreviations from the document a parent might not know. Put each on its own line as \"- word: a short plain explanation\". Reply with only the list."),
        ])
    }
}

/// Explains a letter or visit document on device, from the HTML the viewer
/// already loaded.
struct DocumentExplanationSheet: View {
    let document: ExplainableDocument
    let html: String
    @Environment(Session.self) private var session

    var body: some View {
        AIExplainSheet(heading: document.label, navigationTitle: document.buttonTitle,
                       instructions: DocumentExplainer.instructions) {
            let child = await ChildContext.load(session, at: document.date ?? .now)
            return DocumentExplainer.brief(for: document, html: html, child: child)
        }
    }
}
