import SwiftUI
import Charts

struct GrowthChartsView: View {
    let patientID: String
    @Environment(Session.self) private var session

    @State private var measurements: [GrowthMeasurement] = []
    @State private var isLoading = true

    @State private var dataSet: GrowthDataSet = .whoGirls0to2
    @State private var selectedMetrics: Set<GrowthMetric> = Set(GrowthMetric.allCases)
    @State private var unit: GrowthUnit = .metric
    @State private var zoomToData = true
    @State private var showsOptions = false

    private var orderedMetrics: [GrowthMetric] {
        GrowthMetric.allCases.filter(selectedMetrics.contains)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                optionsCard
                dataSetHeader

                if isLoading {
                    ForEach(0..<2, id: \.self) { _ in chartSkeleton }
                } else if measurements.isEmpty {
                    ContentUnavailableView("No measurements yet", systemImage: "chart.line.uptrend.xyaxis",
                                           description: Text("Height and weight recorded at visits will appear here."))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 40)
                } else if orderedMetrics.isEmpty {
                    emptyCard("Choose at least one measurement type in Chart options.")
                } else {
                    ForEach(orderedMetrics) { metric in
                        GrowthChartCard(metric: metric, dataSet: dataSet, unit: unit,
                                        zoomToData: zoomToData, measurements: measurements)
                    }
                }

                disclaimer
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Growth Charts")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    // MARK: - Chart options

    private var optionsCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            DisclosureGroup(isExpanded: $showsOptions) {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Data set")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Picker("Data set", selection: $dataSet) {
                            ForEach(GrowthDataSet.all) { set in
                                Text(set.name).tag(set)
                            }
                        }
                        .pickerStyle(.menu)
                        .tint(Theme.brand)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Measurement types")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        ForEach(GrowthMetric.allCases) { metric in
                            Toggle(metric.title, isOn: Binding(
                                get: { selectedMetrics.contains(metric) },
                                set: { isOn in
                                    if isOn { selectedMetrics.insert(metric) }
                                    else { selectedMetrics.remove(metric) }
                                }))
                            .tint(Theme.brand)
                        }
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Unit of measurement")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Picker("Unit", selection: $unit) {
                            ForEach(GrowthUnit.allCases) { unit in
                                Text(unit.title).tag(unit)
                            }
                        }
                        .pickerStyle(.segmented)
                    }

                    Toggle("Zoom chart to data", isOn: $zoomToData)
                        .tint(Theme.brand)
                }
                .padding(.top, 16)
            } label: {
                Text("Chart options")
                    .font(.headline)
                    .foregroundStyle(Theme.ink)
            }
            .tint(Theme.brand)
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 20))
    }

    private var dataSetHeader: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(dataSet.name)
                .font(.title3.bold())
                .foregroundStyle(Theme.ink)
            Text("Source: \(dataSet.source)")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var chartSkeleton: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Placeholder chart").font(.headline)
            RoundedRectangle(cornerRadius: 12).fill(Color.gray.opacity(0.25)).frame(height: 220)
            Text("Placeholder chart caption text").font(.subheadline)
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 20))
        .redacted(reason: .placeholder)
    }

    private func emptyCard(_ text: String) -> some View {
        Text(text)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 20))
    }

    private var disclaimer: some View {
        Label("""
            Percentile curves shown here are approximate sample data for this \
            preview, not the official WHO tables. Always discuss your child's \
            growth with their care team.
            """, systemImage: "info.circle")
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.top, 4)
    }

    private func load() async {
        isLoading = true
        measurements = (try? await session.service.growthMeasurements(for: patientID)) ?? []
        isLoading = false
    }
}

// MARK: - One chart

private struct GrowthChartCard: View {
    let metric: GrowthMetric
    let dataSet: GrowthDataSet
    let unit: GrowthUnit
    let zoomToData: Bool
    let measurements: [GrowthMeasurement]

    @State private var showsTable = false
    @State private var showsAllRows = false

    private var reference: GrowthReference { dataSet.reference(for: metric) }

    /// A measurement reduced to the x/y pair this chart plots.
    private struct Plotted: Identifiable {
        let id: String
        let date: Date
        let x: Double
        let y: Double
        let percentile: Double?
    }

    private var points: [Plotted] {
        measurements.compactMap { measurement in
            let rawX: Double
            let rawY: Double
            switch metric {
            case .lengthForAge: rawX = measurement.ageMonths; rawY = measurement.heightCm
            case .weightForAge: rawX = measurement.ageMonths; rawY = measurement.weightKg
            case .weightForLength: rawX = measurement.heightCm; rawY = measurement.weightKg
            case .bmiForAge: rawX = measurement.ageMonths; rawY = measurement.bmi
            }
            guard reference.xRange.contains(rawX) else { return nil }
            return Plotted(id: measurement.id, date: measurement.date,
                           x: displayX(rawX), y: displayY(rawY),
                           percentile: reference.percentile(of: rawY, at: rawX))
        }
    }

    /// Curve samples across the visible x range.
    private struct CurvePoint: Identifiable {
        let id = UUID()
        let x: Double
        let y: Double
        let percentile: Percentile
    }

    private var curves: [CurvePoint] {
        let range = visibleRawXRange
        let steps = 60
        let stride = (range.upperBound - range.lowerBound) / Double(steps)
        return Percentile.allCases.flatMap { percentile in
            (0...steps).compactMap { step in
                let x = range.lowerBound + Double(step) * stride
                guard let y = reference.value(at: x, percentile: percentile) else { return nil }
                return CurvePoint(x: displayX(x), y: displayY(y), percentile: percentile)
            }
        }
    }

    /// The x range to draw, in reference units, before display conversion.
    private var visibleRawXRange: ClosedRange<Double> {
        let full = reference.xRange
        guard zoomToData, !measurements.isEmpty else { return full }
        let xs: [Double] = measurements.map {
            metric.isAgeBased ? $0.ageMonths : $0.heightCm
        }
        guard let min = xs.min(), let max = xs.max() else { return full }
        let pad = Swift.max((max - min) * 0.15, metric.isAgeBased ? 1.5 : 3)
        return Swift.max(full.lowerBound, min - pad)...Swift.min(full.upperBound, max + pad)
    }

    /// x is a length for weight-for-length, so it converts; ages don't.
    private func displayX(_ value: Double) -> Double {
        metric.isAgeBased ? value : unit.length(value)
    }

    private func displayY(_ value: Double) -> Double {
        switch metric {
        case .lengthForAge: unit.length(value)
        case .weightForAge, .weightForLength: unit.mass(value)
        case .bmiForAge: value
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(metric.title)
                .font(.headline)
                .foregroundStyle(Theme.ink)

            chart
            legend
            table
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 20))
    }

    private var chart: some View {
        Chart {
            ForEach(curves) { point in
                LineMark(
                    x: .value(metric.xLabel(metric: unit), point.x),
                    y: .value(metric.yLabel(metric: unit), point.y),
                    series: .value("Percentile", point.percentile.label))
                .foregroundStyle(point.percentile.color)
                .lineStyle(StrokeStyle(lineWidth: point.percentile.isMedian ? 2.2 : 1.2))
            }

            ForEach(points) { point in
                PointMark(
                    x: .value(metric.xLabel(metric: unit), point.x),
                    y: .value(metric.yLabel(metric: unit), point.y))
                .foregroundStyle(Theme.ink)
                .symbolSize(70)
            }
        }
        .chartLegend(.hidden)
        .chartXAxisLabel(metric.xLabel(metric: unit), position: .bottom, alignment: .center)
        .chartYAxisLabel(metric.yLabel(metric: unit), position: .leading, alignment: .center)
        .chartYScale(domain: .automatic(includesZero: false))
        .frame(height: 260)
        .accessibilityLabel("\(metric.title) chart")
        .accessibilityValue(accessibilitySummary)
    }

    private var accessibilitySummary: String {
        guard let latest = points.last else { return "No measurements" }
        let value = latest.y.formatted(.number.precision(.fractionLength(1)))
        guard let percentile = latest.percentile else { return "Latest \(value)" }
        return "Latest \(value), around the \(percentile.formatted(.number.precision(.fractionLength(0)))) percentile"
    }

    private var legend: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())],
                  alignment: .leading, spacing: 6) {
            ForEach(Percentile.allCases.reversed()) { percentile in
                HStack(spacing: 8) {
                    Capsule()
                        .fill(percentile.color)
                        .frame(width: 18, height: 3)
                    Text("\(percentile.label) percentile")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: Data table

    private var table: some View {
        DisclosureGroup(isExpanded: $showsTable) {
            VStack(spacing: 0) {
                header
                let rows = showsAllRows ? Array(points.reversed()) : Array(points.reversed().prefix(5))
                ForEach(rows) { point in
                    Divider()
                    row(point)
                }
                if points.count > 5 {
                    Divider()
                    Button(showsAllRows ? "Show fewer" : "Show all \(points.count)") {
                        withAnimation { showsAllRows.toggle() }
                    }
                    .font(.subheadline.weight(.medium))
                    .padding(.vertical, 10)
                }
            }
            .padding(.top, 10)
        } label: {
            Text("Data table")
                .font(.subheadline.weight(.semibold))
        }
        .tint(Theme.brand)
    }

    private var header: some View {
        HStack {
            Text("Date").frame(maxWidth: .infinity, alignment: .leading)
            Text(metric.isAgeBased ? "Age" : "Length").frame(width: 54, alignment: .trailing)
            Text("Value").frame(width: 66, alignment: .trailing)
            Text("Pctl").frame(width: 44, alignment: .trailing)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
    }

    private func row(_ point: Plotted) -> some View {
        HStack {
            Text(point.date.mediumDate)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(point.x.formatted(.number.precision(.fractionLength(1))))
                .frame(width: 54, alignment: .trailing)
                .foregroundStyle(.secondary)
            Text(point.y.formatted(.number.precision(.fractionLength(1))))
                .fontWeight(.semibold)
                .frame(width: 66, alignment: .trailing)
            Text(point.percentile.map { $0.formatted(.number.precision(.fractionLength(1))) } ?? "—")
                .frame(width: 44, alignment: .trailing)
                .foregroundStyle(.secondary)
        }
        .font(.footnote)
        .padding(.vertical, 8)
    }
}
