import Charts
import SwiftUI

/// Home's Medication card, Health-style: today's progress as a ring with
/// the next dose, a week of dose bars underneath, and the medicines by name.
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
                best = (medication.commonName ?? medication.displayName, dose.scheduled)
            }
        }
        return best
    }

    private var names: String {
        let shown = medications.prefix(3).map { $0.commonName ?? $0.displayName }
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
                        ProgressRing(progress: progress, color: .green)
                            .frame(width: 58, height: 58)
                            .overlay {
                                Text("\(today.filter { $0.status != nil }.count)/\(today.count)")
                                    .font(.system(.subheadline, design: .rounded).bold())
                            }
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
                    WeekDoseChart(days: lastSevenDays.map { ($0, DayProgress(doses(on: $0))) })
                        .frame(height: 74)
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

    private var lastSevenDays: [Date] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        return (0..<7).reversed().compactMap { calendar.date(byAdding: .day, value: -$0, to: today) }
    }
}

/// A ring like the Health app's: green for doses taken, grey for skipped.
struct ProgressRing: View {
    let progress: DayProgress
    let color: Color

    var body: some View {
        ZStack {
            Circle().stroke(color.opacity(0.18), lineWidth: 8)
            Circle()
                .trim(from: 0, to: progress.taken)
                .stroke(color, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Circle()
                .trim(from: progress.taken, to: progress.taken + progress.skipped)
                .stroke(Color.gray.opacity(0.5), style: StrokeStyle(lineWidth: 8, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .animation(.spring, value: progress)
        .accessibilityElement()
        .accessibilityLabel("\(Int((progress.taken * 100).rounded())) percent of today's doses taken")
    }
}

/// Seven small bars: the share of each day's doses taken (green) and
/// skipped (grey). Days with nothing scheduled stay empty.
private struct WeekDoseChart: View {
    let days: [(date: Date, progress: DayProgress?)]

    private struct Bar: Identifiable {
        let date: Date
        let kind: String
        let value: Double
        var id: String { "\(date.timeIntervalSince1970)-\(kind)" }
    }

    private var bars: [Bar] {
        days.flatMap { day -> [Bar] in
            guard let p = day.progress else { return [] }
            return [Bar(date: day.date, kind: "Taken", value: p.taken),
                    Bar(date: day.date, kind: "Skipped", value: p.skipped)]
        }
    }

    var body: some View {
        Chart {
            ForEach(bars) { bar in
                BarMark(x: .value("Day", bar.date, unit: .day), y: .value("Share", bar.value), width: .ratio(0.55))
                    .foregroundStyle(by: .value("Status", bar.kind))
                    .clipShape(.rect(cornerRadius: 3))
            }
        }
        .chartForegroundStyleScale(["Taken": Color.green, "Skipped": Color.gray.opacity(0.45)])
        .chartLegend(.hidden)
        .chartYScale(domain: 0...1)
        .chartYAxis(.hidden)
        .chartXAxis {
            AxisMarks(values: days.map(\.date)) { value in
                AxisValueLabel(format: .dateTime.weekday(.narrow), centered: true)
            }
        }
        .accessibilityLabel("Doses taken over the last seven days")
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
        SummaryCard(category: "Immunisations", systemImage: "syringe.fill", color: color,
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

/// A countdown to the next visit and a timeline of the next few months'
/// appointments, so Home shows at a glance how busy the coming weeks are.
struct VisitTimelineCard: View {
    let upcoming: [Appointment]

    private let color = Feature.visits.tileArt.color

    private var window: ClosedRange<Date> {
        let start = Calendar.current.startOfDay(for: .now)
        let latest = upcoming.map(\.date).max() ?? start
        // At least three months, stretched to fit the last booked visit (up to a year).
        let threeMonths = Calendar.current.date(byAdding: .month, value: 3, to: start) ?? start
        let year = Calendar.current.date(byAdding: .year, value: 1, to: start) ?? start
        return start...min(max(latest, threeMonths), year)
    }

    private var shown: [Appointment] { upcoming.filter { window.contains($0.date) } }

    private var daysUntilNext: Int? {
        guard let next = upcoming.first else { return nil }
        let calendar = Calendar.current
        return calendar.dateComponents([.day], from: calendar.startOfDay(for: .now),
                                       to: calendar.startOfDay(for: next.date)).day
    }

    var body: some View {
        SummaryCard(category: "Coming Up", systemImage: "calendar", color: color,
                    detail: "\(shown.count) visit\(shown.count == 1 ? "" : "s")") {
            VStack(alignment: .leading, spacing: 12) {
                if let days = daysUntilNext, let next = upcoming.first {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(days <= 0 ? "Today" : days == 1 ? "Tomorrow" : "\(days)")
                            .font(.system(size: 34, weight: .bold, design: .rounded))
                        if days > 1 {
                            Text("days").font(.headline).foregroundStyle(.secondary)
                        }
                    }
                    Text("until \(next.title)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Chart {
                    RuleMark(x: .value("Today", Date.now))
                        .foregroundStyle(.secondary.opacity(0.5))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    ForEach(shown) { visit in
                        PointMark(x: .value("Date", visit.date), y: .value("Row", 0))
                            .symbol(visit.isTelehealth ? .square : .circle)
                            .symbolSize(visit.id == upcoming.first?.id ? 160 : 90)
                            .foregroundStyle(color)
                    }
                }
                .chartXScale(domain: window)
                .chartYAxis(.hidden)
                .chartYScale(domain: -1...1)
                .chartXAxis {
                    AxisMarks(values: .stride(by: .month)) { _ in
                        AxisGridLine()
                        AxisValueLabel(format: .dateTime.month(.abbreviated))
                    }
                }
                .frame(height: 64)
                .accessibilityLabel("Timeline of \(shown.count) upcoming visits")
                if shown.contains(where: \.isTelehealth) {
                    Label("Squares are telehealth", systemImage: "square.fill")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

/// The last three months of results as a donut: within range, outside it,
/// and results with no range to compare (cultures, imaging reports).
struct ResultsOverviewCard: View {
    let results: [TestResult]
    @Environment(Session.self) private var session
    @State private var counts: (within: Int, outside: Int, other: Int)?

    /// Enough to be representative without fetching every result's details.
    private static let maxResults = 20

    private var recent: [TestResult] {
        let start = Calendar.current.date(byAdding: .month, value: -3, to: .now) ?? .now
        return Array(results.filter { $0.date >= start }.prefix(Self.maxResults))
    }

    private struct Slice: Identifiable {
        let label: String
        let count: Int
        let color: Color
        var id: String { label }
    }

    var body: some View {
        let recent = recent
        SummaryCard(category: "Last 3 Months", systemImage: "chart.pie.fill",
                    color: Feature.testResults.tileArt.color,
                    detail: "\(recent.count) result\(recent.count == 1 ? "" : "s")") {
            if let counts {
                let slices = [
                    Slice(label: "Within range", count: counts.within, color: Theme.green),
                    Slice(label: "Outside range", count: counts.outside, color: .orange),
                    Slice(label: "No range", count: counts.other, color: Color.gray.opacity(0.45))
                ].filter { $0.count > 0 }
                HStack(spacing: 18) {
                    Chart(slices) { slice in
                        SectorMark(angle: .value("Results", slice.count), innerRadius: .ratio(0.62),
                                   angularInset: 2)
                            .foregroundStyle(slice.color)
                            .cornerRadius(3)
                    }
                    .frame(width: 84, height: 84)
                    .overlay {
                        Text("\(recent.count)")
                            .font(.system(.title3, design: .rounded).bold())
                    }
                    .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(slices) { slice in
                            HStack(spacing: 8) {
                                Circle().fill(slice.color).frame(width: 9, height: 9)
                                Text("\(slice.count)")
                                    .font(.subheadline.weight(.semibold).monospacedDigit())
                                Text(slice.label)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, minHeight: 84)
            }
        }
        .task(id: recent.map(\.id)) { await count(recent) }
    }

    private func count(_ recent: [TestResult]) async {
        let service = session.service, patientID = session.patientID
        var statuses: [TestResult.RangeStatus?] = []
        await withTaskGroup(of: TestResult.self) { group in
            for result in recent {
                group.addTask {
                    (try? await service.testResultDetails(result, for: patientID)) ?? result
                }
            }
            // Worked out here, on the main actor, where `rangeStatus` lives.
            for await detailed in group { statuses.append(detailed.rangeStatus) }
        }
        counts = (statuses.filter { $0 == .within }.count,
                  statuses.filter { $0 == .outside }.count,
                  statuses.filter { $0 == nil }.count)
    }
}
