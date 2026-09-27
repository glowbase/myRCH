import SwiftUI
import Charts

/// Growth charts from the portal: its reference sets (e.g. WHO, CDC), their
/// percentile curves, and the child's measurements with the portal's
/// percentile for each. Demo mode supplies approximate sample curves in the
/// same shape.
struct GrowthChartsView: View {
    let patientID: String
    @Environment(Session.self) private var session

    @State private var datasets: [GrowthDataset] = []
    @State private var isLoading = true
    @State private var failed = false

    @State private var datasetID: String?
    /// Chart kinds switched off in Chart Options (kinds are shared across
    /// sets, so choices carry over when switching set).
    @State private var hiddenKinds: Set<String> = []
    @State private var unit: GrowthUnit = .metric
    @State private var zoomToData = true
    @State private var showsOptions = false

    private var dataset: GrowthDataset? {
        datasets.first { $0.id == datasetID } ?? datasets.first
    }

    /// Charts shown: switched on, and with at least one measurement.
    private var visibleCharts: [GrowthChart] {
        (dataset?.charts ?? []).filter { !$0.points.isEmpty && !hiddenKinds.contains($0.kind) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if let dataset { dataSetHeader(dataset) }

                if isLoading {
                    ForEach(0..<2, id: \.self) { _ in chartSkeleton }
                } else if failed {
                    ContentUnavailableView("Couldn't load growth charts", systemImage: "exclamationmark.triangle",
                                           description: Text("Pull down to try again."))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 40)
                } else if dataset?.charts.allSatisfy({ $0.points.isEmpty }) ?? true {
                    ContentUnavailableView("No measurements yet", systemImage: "chart.line.uptrend.xyaxis",
                                           description: Text("Height and weight recorded at visits will appear here."))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 40)
                } else if visibleCharts.isEmpty {
                    emptyCard("Choose at least one measurement type in Chart Options (the gear button).")
                } else {
                    ForEach(visibleCharts) { chart in
                        GrowthChartCard(chart: chart, unit: unit, zoomToData: zoomToData)
                    }
                }

                if let dataset { disclaimer(dataset) }
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Growth Charts")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Chart Options", systemImage: "gearshape") { showsOptions = true }
                    .disabled(datasets.isEmpty)
            }
        }
        .sheet(isPresented: $showsOptions) { optionsSheet }
        .task { await load() }
        .refreshable {
            await session.refreshData()
            await load()
        }
    }

    // MARK: - Chart options

    /// Changes apply to the charts behind the sheet straight away.
    private var optionsSheet: some View {
        NavigationStack {
            Form {
                Section("Data Set") {
                    Picker("Data set", selection: Binding(get: { dataset?.id }, set: { datasetID = $0 })) {
                        ForEach(datasets) { set in
                            Text(set.name).tag(Optional(set.id))
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }

                Section {
                    ForEach(dataset?.charts ?? []) { chart in
                        Toggle(isOn: Binding(
                            get: { !hiddenKinds.contains(chart.kind) },
                            set: { isOn in
                                if isOn { hiddenKinds.remove(chart.kind) } else { hiddenKinds.insert(chart.kind) }
                            })) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(chart.title)
                                if chart.points.isEmpty {
                                    Text("No measurements recorded")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .disabled(chart.points.isEmpty)
                    }
                } header: {
                    Text("Measurement Types")
                } footer: {
                    if visibleCharts.isEmpty {
                        Text("Turn on at least one to see a chart.")
                    }
                }

                Section("Unit of Measurement") {
                    Picker("Unit", selection: $unit) {
                        ForEach(GrowthUnit.allCases) { unit in
                            Text(unit.title).tag(unit)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }

                Section {
                    Toggle("Zoom Chart to Data", isOn: $zoomToData)
                } footer: {
                    Text("Shows just the ages and values that have measurements, instead of the whole reference range.")
                }
            }
            .tint(Theme.brand)
            .navigationTitle("Chart Options")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { showsOptions = false }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func dataSetHeader(_ dataset: GrowthDataset) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(dataset.name)
                .font(.title3.bold())
                .foregroundStyle(Theme.ink)
            if !dataset.source.isEmpty {
                Text("Source: \(dataset.source)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
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

    private func disclaimer(_ dataset: GrowthDataset) -> some View {
        let text = dataset.isSample
            ? "Percentile curves shown here are approximate sample data for this demo, not the official tables. Always discuss your child's growth with their care team."
            : "Percentiles and curves are as provided by the hospital's records. Always discuss your child's growth with their care team."
        return Label(text, systemImage: "info.circle")
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.top, 4)
    }

    private func load() async {
        if datasets.isEmpty { isLoading = true }
        do {
            datasets = try await session.service.growthCharts(for: patientID)
            failed = false
        } catch {
            failed = datasets.isEmpty
        }
        isLoading = false
    }
}

// MARK: - Units

extension GrowthUnit {
    /// Converts a value on an axis, going by the unit in its label:
    /// "(cm)" is a length, "(kg)" a mass; anything else (BMI, age) is left alone.
    func convert(_ value: Double, axis label: String) -> Double {
        if label.contains("(cm)") { return length(value) }
        if label.contains("(kg)") { return mass(value) }
        return value
    }

    /// The axis label in these units, e.g. "Weight (lb)", "BMI (kg/m²)".
    func label(_ label: String) -> String {
        label
            .replacingOccurrences(of: "(cm)", with: "(\(lengthLabel))")
            .replacingOccurrences(of: "(kg)", with: "(\(massLabel))")
            .replacingOccurrences(of: "kg/m2", with: "kg/m²")
    }
}

extension GrowthCurve {
    /// "3rd percentile", worked out from the number (the portal's own labels
    /// have typos such as "3nd").
    var label: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .ordinal
        return "\(formatter.string(from: NSNumber(value: percentile)) ?? "\(Int(percentile))") percentile"
    }

    /// The colour of the closest standard percentile line (so a CDC 3rd
    /// uses the WHO 2nd's colour, and so on).
    var color: Color {
        (Percentile.allCases.min { abs($0.rawValue - percentile) < abs($1.rawValue - percentile) } ?? .p50).color
    }

    var isMedian: Bool { percentile == 50 }
}

// MARK: - One chart

private struct GrowthChartCard: View {
    let chart: GrowthChart
    let unit: GrowthUnit
    let zoomToData: Bool

    @State private var showsTable = false
    @State private var showsAllRows = false

    private var xLabel: String { unit.label(chart.xLabel) }
    private var yLabel: String { unit.label(chart.yLabel) }

    /// The x range to draw, in the portal's units, before conversion.
    private var visibleXRange: ClosedRange<Double> {
        let full = chart.xRange
        guard zoomToData, let min = chart.points.map(\.x).min(), let max = chart.points.map(\.x).max() else { return full }
        let pad = Swift.max((max - min) * 0.15, chart.isAgeBased ? 1.5 : 3)
        return Swift.max(full.lowerBound, min - pad)...Swift.min(full.upperBound, max + pad)
    }

    private struct CurvePoint: Identifiable {
        let id = UUID()
        let x: Double
        let y: Double
        let curve: GrowthCurve
    }

    /// Curve points within the visible range, converted for display.
    private var curvePoints: [CurvePoint] {
        let range = visibleXRange
        return chart.curves.flatMap { curve in
            curve.points.filter { range.contains($0.x) }.map {
                CurvePoint(x: unit.convert($0.x, axis: chart.xLabel), y: unit.convert($0.y, axis: chart.yLabel), curve: curve)
            }
        }
    }

    private var points: [GrowthPoint] {
        chart.points.filter { visibleXRange.contains($0.x) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(chart.title)
                .font(.headline)
                .foregroundStyle(Theme.ink)

            chartView
            legend
            table
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 20))
    }

    private var chartView: some View {
        Chart {
            ForEach(curvePoints) { point in
                LineMark(
                    x: .value(xLabel, point.x),
                    y: .value(yLabel, point.y),
                    series: .value("Percentile", point.curve.label))
                .foregroundStyle(point.curve.color)
                .lineStyle(StrokeStyle(lineWidth: point.curve.isMedian ? 2.2 : 1.2))
            }

            ForEach(points) { point in
                PointMark(
                    x: .value(xLabel, unit.convert(point.x, axis: chart.xLabel)),
                    y: .value(yLabel, unit.convert(point.y, axis: chart.yLabel)))
                .foregroundStyle(Theme.ink)
                .symbolSize(70)
            }
        }
        .chartLegend(.hidden)
        .chartXAxisLabel(xLabel, position: .bottom, alignment: .center)
        .chartYAxisLabel(yLabel, position: .leading, alignment: .center)
        .chartYScale(domain: .automatic(includesZero: false))
        .frame(height: 260)
        .accessibilityLabel("\(chart.title) chart")
        .accessibilityValue(accessibilitySummary)
    }

    private var accessibilitySummary: String {
        guard let latest = chart.points.last else { return "No measurements" }
        let value = unit.convert(latest.y, axis: chart.yLabel).formatted(.number.precision(.fractionLength(1)))
        guard let percentile = latest.percentile else { return "Latest \(value)" }
        return "Latest \(value), around the \(percentile.formatted(.number.precision(.fractionLength(0)))) percentile"
    }

    private var legend: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())],
                  alignment: .leading, spacing: 6) {
            ForEach(chart.curves.reversed()) { curve in
                HStack(spacing: 8) {
                    Capsule()
                        .fill(curve.color)
                        .frame(width: 18, height: 3)
                    Text(curve.label)
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
                let newestFirst = Array(chart.points.reversed())
                let rows = showsAllRows ? newestFirst : Array(newestFirst.prefix(5))
                ForEach(rows) { point in
                    Divider()
                    row(point)
                }
                if chart.points.count > 5 {
                    Divider()
                    Button(showsAllRows ? "Show fewer" : "Show all \(chart.points.count)") {
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
            Text(chart.isAgeBased ? "Age" : "Length").frame(width: 54, alignment: .trailing)
            Text("Value").frame(width: 66, alignment: .trailing)
            Text("Pctl").frame(width: 44, alignment: .trailing)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
    }

    private func row(_ point: GrowthPoint) -> some View {
        HStack {
            Text(point.date.mediumDate)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(unit.convert(point.x, axis: chart.xLabel).formatted(.number.precision(.fractionLength(1))))
                .frame(width: 54, alignment: .trailing)
                .foregroundStyle(.secondary)
            Text(unit.convert(point.y, axis: chart.yLabel).formatted(.number.precision(.fractionLength(1))))
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
