import SwiftUI

enum ImmunisationExplainer {
    static let instructions = """
        You are explaining a vaccine a child has had. Keep schedules general: \
        the portal doesn't say which doses are due, so never say a dose is \
        due or overdue, and say the GP or care team can confirm what's next. \
        Don't give medical advice about whether to vaccinate.
        """

    /// The vaccine, its products, and each dose with the child's age then,
    /// so the model can tell a baby's schedule from a booster.
    static func brief(for group: ImmunisationGroup, doses: [ImmunisationDose],
                      birthDate: Date?, child: ChildContext) -> AIBrief {
        var lines = ["Vaccine: \(group.name)"]
        if let age = child.ageLine("Child's age now") { lines.append(age) }
        let products = Set(doses.compactMap(\.productName)).sorted()
        if !products.isEmpty { lines.append("Products recorded: \(products.joined(separator: "; "))") }
        lines.append("Doses on record, oldest first:")
        for date in group.dates.sorted() {
            let age = birthDate.map { " (aged \($0.ageDescription(at: date)))" } ?? ""
            lines.append("- \(date.mediumDate)\(age)")
        }

        var sections = [
            AISection(title: "What it protects against", systemImage: "shield.lefthalf.filled",
                      request: "In two or three short sentences, explain what this vaccine protects against and what those illnesses can do to a child. Reply with only the explanation."),
            AISection(title: "Why children have it", systemImage: "calendar",
                      request: "Now, in two or three short sentences, explain in general terms why this vaccine is given in childhood in Australia and why more than one dose is often needed. Reply with only the explanation."),
            AISection(title: "Common reactions", systemImage: "bandage",
                      request: "Now, in two or three short sentences, describe the common, mild reactions children can have after this vaccine and how long they usually last, and say to contact the GP or care team if worried. Reply with only the explanation."),
        ]
        if let conditions = child.conditionsSection(about: "this vaccine",
                                                    example: "such as why it's especially recommended for children with that condition") {
            sections.append(conditions)
        }
        return AIBrief(context: lines.joined(separator: "\n"), sections: sections)
    }
}

/// Explains a vaccine on device.
struct ImmunisationExplanationSheet: View {
    let group: ImmunisationGroup
    let doses: [ImmunisationDose]
    @Environment(Session.self) private var session

    var body: some View {
        AIExplainSheet(heading: group.name, navigationTitle: "Explain Immunisation",
                       instructions: ImmunisationExplainer.instructions) {
            let child = await ChildContext.load(session)
            let birthDate = session.profile?.linkedAccounts.first { $0.id == session.patientID }?.dateOfBirth
            return ImmunisationExplainer.brief(for: group, doses: doses, birthDate: birthDate, child: child)
        }
    }
}
