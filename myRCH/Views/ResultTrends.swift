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

/// Health-style trend cards for a result's values, each with a time-range
/// picker, the normal range shaded, and the latest value large.
struct ResultTrendsSection: View {
    let result: TestResult
    @Environment(Session.self) private var session
    @State private var trends: [ComponentTrend] = []

    var body: some View {
        // A stack, not a Group, so `.task` runs while it's still empty.
        VStack(alignment: .leading, spacing: 12) {
            if !trends.isEmpty {
                SummarySectionHeader<Feature>(title: "Trends")
                ForEach(trends) { TrendCard(trend: $0) }
            }
        }
        .task(id: result.id) {
            trends = await ResultHistory.trends(for: result, service: session.service, patientID: session.patientID)
        }
    }
}

private struct TrendCard: View {
    let trend: ComponentTrend

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

            VStack(alignment: .leading, spacing: 2) {
                Text(trend.name.uppercased())
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                if let latest = trend.latest {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(latest.value.formatted(.number.precision(.fractionLength(0...2))))
                            .font(.system(size: 34, weight: .bold, design: .rounded))
                        Text(trend.unit)
                            .font(.headline)
                            .foregroundStyle(.secondary)
                    }
                    Text("Latest, \(latest.date.mediumDate)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            if shown.count >= 1 {
                chart.frame(height: 170)
            } else {
                Text("No values in this period.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 80)
            }

            if let low = trend.normalLow, let high = trend.normalHigh {
                Label("Normal range \(low.formatted()) – \(high.formatted()) \(trend.unit)", systemImage: "rectangle.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: Theme.cardRadius))
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
