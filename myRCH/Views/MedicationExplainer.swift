import SwiftUI

enum MedicationExplainer {
    static let instructions = """
        You are explaining a medicine prescribed for a child. Never give, \
        suggest or change doses: the instructions from the child's care team \
        always come first. If you don't recognise the medicine, say so \
        rather than guessing.
        """

    static func brief(for medication: Medication, child: ChildContext) -> AIBrief {
        var lines: [String] = []
        if let age = child.ageLine() { lines.append(age) }
        lines.append("Medicine: \(medication.sourceName ?? medication.displayName)")
        if let commonName = medication.commonName { lines.append("Also known as: \(commonName)") }
        if let form = medication.productForm { lines.append("Form: \(form)") }
        if !medication.instructions.isEmpty {
            lines.append("The care team's instructions: \(medication.instructions)")
        }
        lines.append("Status: \(medication.isActive ? "currently taking" : "no longer taking")")

        var sections = [
            AISection(title: "What it's for", systemImage: "questionmark.circle.fill",
                      request: "In two or three short sentences, explain what this medicine is and what it's commonly used for in children. Reply with only the explanation."),
            AISection(title: "How it's usually taken", systemImage: "hand.raised.fill",
                      request: "Now, in two or three short sentences, describe how this kind of medicine is usually taken or given, with any common practical tips, such as with food or rinsing the mouth afterwards. Don't mention doses, and say the care team's instructions come first. Reply with only the explanation."),
            AISection(title: "Common side effects", systemImage: "exclamationmark.circle",
                      request: "Now, in two to four short sentences, describe common side effects families might notice, and say to contact the care team if they're worried. Reply with only the explanation."),
        ]
        if let conditions = child.conditionsSection(about: "this medicine",
                                                    example: "such as why it's often used with that condition") {
            sections.append(conditions)
        }
        return AIBrief(context: lines.joined(separator: "\n"), sections: sections)
    }
}

/// Explains a medication on device.
struct MedicationExplanationSheet: View {
    let medication: Medication
    @Environment(Session.self) private var session

    var body: some View {
        AIExplainSheet(heading: medication.reminderName, navigationTitle: "Explain Medication",
                       instructions: MedicationExplainer.instructions) {
            MedicationExplainer.brief(for: medication, child: await ChildContext.load(session))
        }
    }
}
