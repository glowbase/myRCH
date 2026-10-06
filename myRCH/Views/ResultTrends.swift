import Charts
import SwiftUI

/// Past values of one measured component (e.g. Haemoglobin) across results
/// of the same test, oldest first.
struct ComponentTrend: Identifiable {
    struct Point: Identifiable {
        let date: Date
        let value: Double
        var id: Date { date }
    }

    var name: String
    var unit: String
    var normalLow: Double?
    var normalHigh: Double?
    var points: [Point]
    var id: String { name }

    var latest: Point? { points.last }
}

enum ResultHistory {
    /// At most this many earlier results are fetched per test, to keep the
    /// number of detail requests reasonable.
    static let maxResults = 12

    /// Trends for every numeric component of `result`, from results with the
    /// same name. Details come from the service's cache where already loaded.
    /// Censored values ("<5") are left out: they aren't a point on a line.
    static func trends(for result: TestResult, service: PortalService, patientID: String) async -> [ComponentTrend] {
        guard let all = try? await service.testResults(for: patientID) else { return [] }
        let same = all.filter { $0.name == result.name }
            .sorted { $0.date > $1.date }
            .prefix(maxResults)
        guard same.count >= 2 else { return [] }

        var detailed: [TestResult] = []
        await withTaskGroup(of: TestResult?.self) { group in
            for item in same {
                group.addTask { try? await service.testResultDetails(item, for: patientID) }
            }
            for await item in group { if let item { detailed.append(item) } }
        }

        var byName: [String: ComponentTrend] = [:]
        for item in detailed.sorted(by: { $0.date < $1.date }) {
            for component in item.components {
                guard let value = component.value, component.qualifier == nil else { continue }
                var trend = byName[component.name] ?? ComponentTrend(name: component.name, unit: component.unit,
                                                                    normalLow: component.normalLow,
                                                                    normalHigh: component.normalHigh, points: [])
                trend.points.append(.init(date: item.date, value: value))
                // The newest result's range is the one to draw.
                trend.normalLow = component.normalLow ?? trend.normalLow
                trend.normalHigh = component.normalHigh ?? trend.normalHigh
                byName[component.name] = trend
            }
        }
        // Keep the components' order from the result being viewed.
        let order = result.components.map(\.name)
        return byName.values
            .filter { $0.points.count >= 2 }
            .sorted { (order.firstIndex(of: $0.name) ?? .max) < (order.firstIndex(of: $1.name) ?? .max) }
    }
}

/// Describes a component's history for the on-device model.
enum TrendSummary {
    static let instructions = """
        You are describing how one of a child's test values has changed over \
        time. Describe the direction (rising, falling, steady or up and \
        down) and where the latest value sits against the normal range. \
        Don't guess at causes.
        """

    static func prompt(for trend: ComponentTrend, age: String?) -> String {
        var lines: [String] = []
        if let age { lines.append("Child's age now: \(age)") }
        lines.append("Test value: \(trend.name)" + (trend.unit.isEmpty ? "" : " (\(trend.unit))"))
        switch (trend.normalLow, trend.normalHigh) {
        case let (low?, high?): lines.append("Normal range: \(low.formatted())–\(high.formatted())")
        case let (nil, high?): lines.append("Normal: below \(high.formatted())")
        case let (low?, nil): lines.append("Normal: above \(low.formatted())")
        case (nil, nil): break
        }
        lines.append("Values, oldest first:")
        for point in trend.points {
            var line = "- \(point.date.mediumDate): \(point.value.formatted(.number.precision(.fractionLength(0...2))))"
            if let low = trend.normalLow, point.value < low { line += " (below range)" }
            if let high = trend.normalHigh, point.value > high { line += " (above range)" }
            lines.append(line)
        }
        lines.append("")
        lines.append("In two or three short sentences, describe how this value has changed over time and where the latest one sits compared with the normal range. Reply with only the description.")
        return lines.joined(separator: "\n")
    }
}

/// A collapsed "Trend" dropdown under a result value: a time-range picker,
/// then the history as a chart (normal range shaded) and as a table.
struct TrendDisclosure: View {
    let trend: ComponentTrend
    @State private var isExpanded = false

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            TrendDetail(trend: trend)
                .padding(.top, 12)
        } label: {
            Label("Trend (\(trend.points.count) results)", systemImage: "chart.xyaxis.line")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.ink)
        }
        .tint(Theme.brand)
    }
}

private struct TrendDetail: View {
    let trend: ComponentTrend
    @Environment(Session.self) private var session

    enum Span: String, CaseIterable, Identifiable {
        case sixMonths = "6M", year = "Y", all = "All"
        var id: String { rawValue }
        func start(from now: Date) -> Date? {
            switch self {
            case .sixMonths: Calendar.current.date(byAdding: .month, value: -6, to: now)
            case .year: Calendar.current.date(byAdding: .year, value: -1, to: now)
            case .all: nil
            }
        }
    }

    @State private var span: Span = .all

    private var shown: [ComponentTrend.Point] {
        guard let start = span.start(from: .now) else { return trend.points }
        return trend.points.filter { $0.date >= start }
    }

    private let color = Feature.testResults.tileArt.color

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("Range", selection: $span) {
                ForEach(Span.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)

            if shown.count >= 1 {
                chart.frame(height: 170)
                if trend.normalLow != nil, trend.normalHigh != nil {
                    Label("Shaded area is the normal range", systemImage: "rectangle.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Divider()
                table
                Divider()
                AIInlineSummary(buttonTitle: "Summarise trend", instructions: TrendSummary.instructions) {
                    TrendSummary.prompt(for: trend, age: await ChildContext.load(session).age)
                }
            } else {
                Text("No values in this period.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 80)
            }
        }
    }

    /// The same values as the chart, newest first, flagged when outside the
    /// normal range with an icon as well as colour.
    private var table: some View {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
            GridRow {
                Text("Date")
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(trend.unit.isEmpty ? "Value" : "Value (\(trend.unit))")
                    .gridColumnAlignment(.trailing)
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            ForEach(shown.reversed()) { point in
                let outside = isOutside(point.value)
                GridRow {
                    Text(point.date.mediumDate)
                    HStack(spacing: 4) {
                        if outside {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.caption)
                        }
                        Text(point.value.formatted(.number.precision(.fractionLength(0...2))))
                            .monospacedDigit()
                    }
                    .foregroundStyle(outside ? Theme.orange : .primary)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(point.value.formatted()) \(trend.unit)")
                    .accessibilityValue(outside ? "Outside normal range" : "")
                }
                .font(.subheadline)
            }
        }
    }

    private var chart: some View {
        Chart {
            if let low = trend.normalLow, let high = trend.normalHigh,
               let first = shown.first?.date, let last = shown.last?.date {
                RectangleMark(xStart: .value("From", first), xEnd: .value("To", last),
                              yStart: .value("Low", low), yEnd: .value("High", high))
                    .foregroundStyle(Theme.green.opacity(0.14))
            }
            ForEach(shown) { point in
                LineMark(x: .value("Date", point.date), y: .value(trend.name, point.value))
                    .foregroundStyle(color)
                    .interpolationMethod(.monotone)
                PointMark(x: .value("Date", point.date), y: .value(trend.name, point.value))
                    .foregroundStyle(isOutside(point.value) ? Color.orange : color)
            }
        }
        .chartYScale(domain: .automatic(includesZero: false))
        .accessibilityLabel("\(trend.name) over time")
    }

    private func isOutside(_ value: Double) -> Bool {
        if let low = trend.normalLow, value < low { return true }
        if let high = trend.normalHigh, value > high { return true }
        return false
    }
}

/// A tiny line of the first measured value's history, for Home's cards.
struct TrendSparkline: View {
    let result: TestResult
    @Environment(Session.self) private var session
    @State private var trend: ComponentTrend?

    var body: some View {
        // A stack, not a Group, so `.task` runs while it's still empty.
        ZStack {
            if let trend {
                Chart(trend.points) { point in
                    LineMark(x: .value("Date", point.date), y: .value(trend.name, point.value))
                        .interpolationMethod(.monotone)
                        .foregroundStyle(Feature.testResults.tileArt.color)
                    if point.id == trend.points.last?.id {
                        PointMark(x: .value("Date", point.date), y: .value(trend.name, point.value))
                            .foregroundStyle(Feature.testResults.tileArt.color)
                    }
                }
                .chartXAxis(.hidden)
                .chartYAxis(.hidden)
                .chartYScale(domain: .automatic(includesZero: false))
                .frame(width: 90, height: 40)
                .accessibilityLabel("\(trend.name) trend")
            }
        }
        .task(id: result.id) {
            trend = await ResultHistory.trends(for: result, service: session.service,
                                               patientID: session.patientID).first
        }
    }
}
