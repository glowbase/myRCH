import Charts
import SwiftUI

/// Home's Medication card, Health-style: today's progress as a filled
/// circle with the next dose, a week of day circles underneath, and the
/// medicines by name.
struct MedicationSummaryCard: View {
    let medications: [Medication]
    @Environment(Session.self) private var session
    @Environment(MedicationStore.self) private var store

    private let color = Feature.medication.tileArt.color

    private func key(_ medication: Medication) -> String {
        MedicationStore.key(patientID: session.patientID, medicationID: medication.id)
    }

    private func doses(on day: Date) -> [MedicationStore.Dose] {
        medications.flatMap { store.doses(on: day, for: key($0)) }
    }

    /// The next dose still to log today, with its medicine's name.
    private var nextDose: (name: String, time: Date)? {
        var best: (name: String, time: Date)?
        for medication in medications {
            for dose in store.doses(for: key(medication)) where dose.status == nil {
                if let current = best, current.time <= dose.scheduled { continue }
                best = (medication.reminderName, dose.scheduled)
            }
        }
        return best
    }

    private var names: String {
        let shown = medications.prefix(3).map(\.reminderName)
        let extra = medications.count - shown.count
        return (shown + (extra > 0 ? ["+\(extra) more"] : [])).joined(separator: " · ")
    }

    var body: some View {
        let today = doses(on: .now)
        SummaryCard(category: "Medication", systemImage: Feature.medication.tileArt.symbol,
                    color: color, detail: today.isEmpty ? nil : "Today") {
            VStack(alignment: .leading, spacing: 14) {
                if let progress = DayProgress(today) {
                    HStack(spacing: 16) {
                        Group {
                            if progress.isComplete {
                                doneMark(allSkipped: progress.taken == 0)
                            } else {
                                DoseCircle(progress: progress,
                                           label: "\(today.filter { $0.status != nil }.count)/\(today.count)",
                                           labelFont: .system(.subheadline, design: .rounded).bold())
                            }
                        }
                        .frame(width: 58, height: 58)
                        .accessibilityElement()
                        .accessibilityLabel("\(Int((progress.taken * 100).rounded())) percent of today's doses taken")
                        VStack(alignment: .leading, spacing: 3) {
                            if let next = nextDose {
                                Text(next.time, format: .dateTime.hour().minute())
                                    .font(.system(.title2, design: .rounded).bold())
                                Text("Next: \(next.name)")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            } else {
                                Text("All logged")
                                    .font(.system(.title2, design: .rounded).bold())
                                Text("Nothing else due today")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    WeekDoseCircles(days: lastSevenDays.map { ($0, DayProgress(doses(on: $0))) })
                } else {
                    Text("\(medications.count) current medication\(medications.count == 1 ? "" : "s")")
                        .font(.system(.title3, design: .rounded).bold())
                    Text("Set reminders on a medication to track doses here.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Text(names)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
    }

    /// Once today is all logged: a tick (or a cross, if every dose was
    /// skipped) on a pale circle, lighter than a solid filled circle.
    private func doneMark(allSkipped: Bool) -> some View {
        let tint = allSkipped ? DoseCircle.skipped : DoseCircle.taken
        return Circle()
            .fill(tint.opacity(0.15))
            .overlay {
                Image(systemName: allSkipped ? "xmark" : "checkmark")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(tint)
            }
    }

    private var lastSevenDays: [Date] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        return (0..<7).reversed().compactMap { calendar.date(byAdding: .day, value: -$0, to: today) }
    }
}

/// The last seven days as `DoseCircle`s, the same circles as the
/// Medication screen's day strip, with today's weekday in bold.
private struct WeekDoseCircles: View {
    let days: [(date: Date, progress: DayProgress?)]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(days, id: \.date) { day in
                let isToday = Calendar.current.isDateInToday(day.date)
                VStack(spacing: 6) {
                    DoseCircle(progress: day.progress, markFont: .caption.weight(.bold))
                        .frame(width: 30, height: 30)
                    Text(day.date.formatted(.dateTime.weekday(.narrow)))
                        .font(.caption2.weight(isToday ? .bold : .medium))
                        .foregroundStyle(isToday ? .primary : .secondary)
                }
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(day.date.formatted(.dateTime.weekday(.wide)))
                .accessibilityValue(Self.describe(day.progress))
            }
        }
    }

    private static func describe(_ progress: DayProgress?) -> String {
        guard let progress else { return "No doses scheduled" }
        var parts: [String] = []
        if progress.taken > 0 { parts.append("\(Int((progress.taken * 100).rounded())) percent taken") }
        if progress.skipped > 0 { parts.append("\(Int((progress.skipped * 100).rounded())) percent skipped") }
        return parts.isEmpty ? "Nothing logged" : parts.joined(separator: ", ")
    }
}

/// Home's Immunisations card: the latest vaccine, and a small chart of how
/// many doses were given each year.
struct ImmunisationSummaryCard: View {
    let groups: [ImmunisationGroup]

    private let color = Feature.immunisations.tileArt.color

    private var latest: (name: String, date: Date)? {
        groups.compactMap { group in group.dates.first.map { (group.name, $0) } }.max { $0.1 < $1.1 }
    }

    private var perYear: [(year: Int, count: Int)] {
        let years = groups.flatMap(\.dates).map { Calendar.current.component(.year, from: $0) }
        return Dictionary(grouping: years, by: { $0 }).map { ($0.key, $0.value.count) }.sorted { $0.year < $1.year }
    }

    var body: some View {
        SummaryCard(category: "Immunisations", systemImage: Feature.immunisations.systemImage, color: color,
                    detail: latest?.date.mediumDate) {
            VStack(alignment: .leading, spacing: 12) {
                if let latest {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(latest.name)
                            .font(.system(.title3, design: .rounded).bold())
                        Text("Most recent · \(groups.count) vaccine\(groups.count == 1 ? "" : "s") on file")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                if perYear.count >= 2 {
                    Chart(perYear.suffix(8), id: \.year) { item in
                        BarMark(x: .value("Year", String(item.year)), y: .value("Doses", item.count), width: .ratio(0.55))
                            .foregroundStyle(color.gradient)
                            .clipShape(.rect(cornerRadius: 3))
                    }
                    .chartYAxis(.hidden)
                    .frame(height: 64)
                    .accessibilityLabel("Immunisation doses given each year")
                }
            }
        }
    }
}

/// Home's Growth section: the latest weight and height with their
/// percentiles, and the child's weight plotted against the median curve.
/// Loads by itself (the growth response is large) and stays hidden until
/// there's something to show.
struct GrowthHomeSection: View {
    @Environment(Session.self) private var session
    @State private var dataset: GrowthDataset?

    private let color = Feature.growthCharts.tileArt.color

    /// Charts against age, picked by name: the portal's kinds differ
    /// between reference sets (WHO, CDC).
    private func chart(_ words: [String], excluding: [String] = [], in dataset: GrowthDataset?) -> GrowthChart? {
        dataset?.charts.first { chart in
            let name = (chart.title + " " + chart.kind).lowercased()
            return (chart.isAgeBased || name.contains("age")) && !chart.points.isEmpty
                && words.contains(where: name.contains) && !excluding.contains(where: name.contains)
        }
    }

    private static let weightWords = (["weight"], ["length", "height", "stature", "bmi"])
    private static let heightWords = (["length", "height", "stature"], ["weight", "head"])

    private var weight: GrowthChart? { chart(Self.weightWords.0, excluding: Self.weightWords.1, in: dataset) }
    private var height: GrowthChart? { chart(Self.heightWords.0, excluding: Self.heightWords.1, in: dataset) }

    var body: some View {
        // A stack, not a Group: an empty Group has no view to run `.task` on,
        // so the data would never load.
        VStack(alignment: .leading, spacing: 12) {
            if weight != nil || height != nil {
                SummarySectionHeader(title: "Growth", destination: Feature.growthCharts)
                NavigationLink(value: Feature.growthCharts) { card }
                    .buttonStyle(.plain)
            }
        }
        .task(id: session.patientID) {
            // The portal's default set first, but only one with measurements.
            let sets = (try? await session.service.growthCharts(for: session.patientID)) ?? []
            dataset = sets.first { set in
                chart(Self.weightWords.0, excluding: Self.weightWords.1, in: set) != nil
                    || chart(Self.heightWords.0, excluding: Self.heightWords.1, in: set) != nil
            }
        }
    }

    private var card: some View {
        SummaryCard(category: "Growth", systemImage: Feature.growthCharts.tileArt.symbol, color: color,
                    detail: (weight?.points.last ?? height?.points.last)?.date.mediumDate) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 24) {
                    if let weight { measure("Weight", weight) }
                    if let height { measure("Height", height) }
                }
                if let weight, weight.points.count >= 2 {
                    weightChart(weight)
                        .frame(height: 90)
                }
            }
        }
    }

    private func measure(_ label: String, _ chart: GrowthChart) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label.uppercased())
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            if let latest = chart.points.last {
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(latest.y.formatted(.number.precision(.fractionLength(0...1))))
                        .font(.system(.title2, design: .rounded).bold())
                    Text(Self.unit(of: chart))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                if let percentile = latest.percentile {
                    Text("\(Self.ordinal(percentile)) percentile")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    /// The child's weights over the median (50th) curve for the same ages.
    private func weightChart(_ chart: GrowthChart) -> some View {
        let xs = chart.points.map(\.x)
        let span = (xs.min() ?? 0)...(xs.max() ?? 0)
        let median = chart.curves.min { abs($0.percentile - 50) < abs($1.percentile - 50) }
        let medianPoints = median?.points.filter { span.contains($0.x) } ?? []
        return Chart {
            ForEach(Array(medianPoints.enumerated()), id: \.offset) { _, point in
                LineMark(x: .value("Age", point.x), y: .value("Median", point.y), series: .value("Line", "Median"))
                    .foregroundStyle(.secondary.opacity(0.4))
                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
            }
            ForEach(chart.points) { point in
                LineMark(x: .value("Age", point.x), y: .value("Weight", point.y), series: .value("Line", "Child"))
                    .foregroundStyle(color)
                    .interpolationMethod(.monotone)
                PointMark(x: .value("Age", point.x), y: .value("Weight", point.y))
                    .foregroundStyle(color)
                    .symbolSize(24)
            }
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartYScale(domain: .automatic(includesZero: false))
        .accessibilityLabel("Weight over time, compared with the 50th percentile")
    }

    /// "Weight (kg)" → "kg".
    private static func unit(of chart: GrowthChart) -> String {
        guard let open = chart.yLabel.lastIndex(of: "("), let close = chart.yLabel.lastIndex(of: ")"),
              open < close else { return "" }
        return String(chart.yLabel[chart.yLabel.index(after: open)..<close])
    }

    /// 42.17 → "42nd".
    private static func ordinal(_ value: Double) -> String {
        let n = Int(value.rounded())
        let suffix = switch (n % 100, n % 10) {
        case (11...13, _): "th"
        case (_, 1): "st"
        case (_, 2): "nd"
        case (_, 3): "rd"
        default: "th"
        }
        return "\(n)\(suffix)"
    }
}
