import SwiftUI

enum GrowthExplainer {
    static let instructions = """
        You are explaining a child's growth charts. Doctors mostly look at \
        whether a child keeps following their own percentile curve over \
        time, not at any single percentile: a child on the 10th percentile \
        who stays there is usually growing as expected. Describe the \
        patterns you're given, and don't say whether a child is underweight \
        or overweight.
        """

    /// Enough points to show a pattern without crowding the context window.
    private static let pointsPerChart = 8

    static func brief(for dataset: GrowthDataset, charts: [GrowthChart], child: ChildContext) -> AIBrief {
        var lines = ["Growth reference: \(dataset.name) (\(dataset.source))"]
        if let age = child.ageLine("Child's age now") { lines.append(age) }
        for chart in charts {
            lines.append("")
            lines.append("\(chart.title) (\(chart.xLabel) against \(chart.yLabel)), oldest first:")
            for point in chart.points.suffix(pointsPerChart) {
                var line = "- \(point.date.mediumDate): \(chart.xLabel) \(point.x.formatted(.number.precision(.fractionLength(0...1)))), \(chart.yLabel) \(point.y.formatted(.number.precision(.fractionLength(0...1))))"
                if let percentile = point.percentile {
                    line += ", \(percentile.formatted(.number.precision(.fractionLength(0)))) percentile"
                }
                lines.append(line)
            }
        }

        var sections = [
            AISection(title: "What percentiles mean", systemImage: "chart.line.uptrend.xyaxis",
                      request: "In two or three short sentences, explain what a growth percentile means, using one of this child's latest measurements as the example. Reply with only the explanation."),
            AISection(title: "How your child is tracking", systemImage: "point.topleft.down.to.point.bottomright.curvepath",
                      request: "Now, in two to four short sentences, describe for each chart whether the measurements stay near the same percentile over time, or move up or down across the curves. Reply with only the description."),
        ]
        if let conditions = child.conditionsSection(about: "these growth measurements",
                                                    example: "such as why growth and weight are watched closely with that condition") {
            sections.append(conditions)
        }
        return AIBrief(context: lines.joined(separator: "\n"), sections: sections)
    }
}

/// Explains the growth charts on screen, on device.
struct GrowthExplanationSheet: View {
    let dataset: GrowthDataset
    let charts: [GrowthChart]
    @Environment(Session.self) private var session

    var body: some View {
        AIExplainSheet(heading: "Growth Charts", navigationTitle: "Explain Growth",
                       instructions: GrowthExplainer.instructions) {
            GrowthExplainer.brief(for: dataset, charts: charts, child: await ChildContext.load(session))
        }
    }
}
