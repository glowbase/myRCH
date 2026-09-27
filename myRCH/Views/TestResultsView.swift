import PDFKit
import SwiftUI

// MARK: - Filtering

/// Which kinds of result to show in the list.
enum ResultKindFilter: String, CaseIterable, Identifiable {
    case all, lab, imaging, pathology

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: "All results"
        case .lab: "Lab tests"
        case .imaging: "Imaging"
        case .pathology: "Pathology"
        }
    }

    func matches(_ kind: TestResult.Kind) -> Bool {
        switch self {
        case .all: true
        case .lab: kind == .lab
        case .imaging: kind == .imaging
        case .pathology: kind == .pathology
        }
    }
}

extension TestResult.Kind {
    var systemImage: String {
        switch self {
        case .lab: "testtube.2"
        // SF Symbols has no X-ray glyph.
        case .imaging: "photo.on.rectangle.angled"
        case .pathology: "microbe"
        }
    }
}

extension TestResult {
    /// An icon for the kind of test, picked from its name (the portal gives
    /// no finer category than lab/imaging). Falls back to the type's icon.
    var systemImage: String {
        let name = name.lowercased()
        func mentions(_ words: String...) -> Bool { words.contains { name.contains($0) } }

        switch kind {
        case .imaging:
            if mentions("ecg", "echo") { return "waveform.path.ecg" }
            if mentions("chest", "lung", "thorax") { return "lungs.fill" }
            if mentions("ultrasound", "us ") { return "dot.radiowaves.left.and.right" }
            return kind.systemImage
        case .pathology:
            return kind.systemImage
        case .lab:
            break
        }
        if mentions("culture", "swab", "pcr", "microscopy", "virus", "viral") { return "microbe" }
        if mentions("allergy", "ige") { return "allergens" }
        if mentions("blood count", "fbc", "haemoglobin", "iron", "ferritin", "blood group", "coagulation") {
            return "drop.fill"
        }
        if mentions("vitamin d") { return "sun.max.fill" }
        if mentions("vitamin", "zinc", "magnesium", "folate", "b12") { return "leaf.fill" }
        if mentions("urine") { return "drop.halffull" }
        return kind.systemImage
    }
}

// MARK: - List

struct TestResultsView: View {
    let patientID: String
    @Environment(Session.self) private var session

    @State private var searchText = ""
    @State private var kindFilter: ResultKindFilter = .all
    @State private var unreadOnly = false
    @State private var abnormalOnly = false

    private var isFiltering: Bool { kindFilter != .all || unreadOnly || abnormalOnly }

    var body: some View {
        AsyncSection {
            try await session.service.testResults(for: patientID)
        } content: { results in
            let filtered = filter(results)
            List {
                ForEach(groupedByMonth(filtered), id: \.month) { group in
                    Section {
                        ForEach(group.results) { result in
                            NavigationLink {
                                TestResultDetailView(result: result)
                            } label: {
                                TestResultRow(result: result)
                            }
                        }
                    } header: {
                        Text(group.month.formatted(.dateTime.month(.wide).year()))
                    }
                }
            }
            .searchable(text: $searchText, prompt: "Search tests, values or clinicians")
            .overlay {
                if results.isEmpty {
                    ContentUnavailableView("No test results yet", systemImage: "testtube.2",
                                           description: Text("Results appear here once the lab releases them to the portal. Some take a few days."))
                } else if filtered.isEmpty {
                    if searchText.isEmpty {
                        ContentUnavailableView("No matching results", systemImage: "line.3.horizontal.decrease.circle",
                                               description: Text("Try changing your filters."))
                    } else {
                        ContentUnavailableView.search(text: searchText)
                    }
                }
            }
        }
        .navigationTitle("Test Results")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                filterMenu
            }
        }
    }

    private var filterMenu: some View {
        Menu {
            Picker("Type", selection: $kindFilter) {
                ForEach(ResultKindFilter.allCases) { filter in
                    Text(filter.title).tag(filter)
                }
            }
            Section {
                Toggle("Unread only", systemImage: "circle.fill", isOn: $unreadOnly)
                Toggle("Outside normal range", systemImage: "exclamationmark.triangle", isOn: $abnormalOnly)
            }
            if isFiltering {
                Button("Clear filters", systemImage: "xmark.circle", role: .destructive) {
                    kindFilter = .all
                    unreadOnly = false
                    abnormalOnly = false
                }
            }
        } label: {
            Image(systemName: isFiltering
                  ? "line.3.horizontal.decrease.circle.fill"
                  : "line.3.horizontal.decrease.circle")
        }
        .accessibilityLabel("Filter results")
    }

    private func filter(_ results: [TestResult]) -> [TestResult] {
        results.filter { result in
            guard kindFilter.matches(result.kind) else { return false }
            if unreadOnly && !result.isUnread { return false }
            if abnormalOnly && !result.isAbnormal { return false }
            guard !searchText.isEmpty else { return true }
            return result.name.localizedCaseInsensitiveContains(searchText)
                || result.orderingProvider.localizedCaseInsensitiveContains(searchText)
                || result.components.contains { $0.name.localizedCaseInsensitiveContains(searchText) }
        }
    }

    private struct MonthGroup {
        let month: Date
        let results: [TestResult]
    }

    /// Buckets results by calendar month, newest month first.
    private func groupedByMonth(_ results: [TestResult]) -> [MonthGroup] {
        let calendar = Calendar.current
        let groups = Dictionary(grouping: results) { result in
            calendar.date(from: calendar.dateComponents([.year, .month], from: result.date)) ?? result.date
        }
        return groups
            .map { MonthGroup(month: $0.key, results: $0.value.sorted(by: TestResult.newestFirst)) }
            .sorted { $0.month > $1.month }
    }
}

/// "Within normal range" / "Outside normal range", as shown in the list and
/// on the result screen. Icon plus words, so it never relies on colour.
struct RangeStatusPill: View {
    let status: TestResult.RangeStatus

    var body: some View {
        let outside = status == .outside
        Label(outside ? "Outside normal range" : "Within normal range",
              systemImage: outside ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
            .font(.caption.weight(.semibold))
            .foregroundStyle(outside ? Theme.orange : Theme.green)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background((outside ? Theme.orange : Theme.green).opacity(0.14), in: .capsule)
    }
}

struct TestResultRow: View {
    @Environment(Session.self) private var session
    let result: TestResult
    /// Values and ranges aren't in the list response, so each row fetches its
    /// details when it scrolls into view (the service caches them, so opening
    /// the result afterwards is instant).
    @State private var detailed: TestResult?

    private var status: TestResult.RangeStatus? { (detailed ?? result).rangeStatus }

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: result.systemImage)
                .font(.title3)
                .foregroundStyle(Feature.testResults.accent)
                .frame(width: 40, height: 40)
                .background(Feature.testResults.accent.opacity(0.12), in: .circle)
            VStack(alignment: .leading, spacing: 3) {
                Text(result.name)
                    .font(.headline)
                    .fontWeight(result.isUnread ? .semibold : .regular)
                Text(result.date.mediumDate)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if let status {
                    RangeStatusPill(status: status)
                        .padding(.top, 2)
                }
            }
            Spacer()
            if result.isUnread {
                Circle().fill(Theme.brand).frame(width: 10, height: 10)
                    .accessibilityLabel("Unread")
            }
        }
        .padding(.vertical, 4)
        .animation(.default, value: status)
        .task(id: result.id) {
            detailed = try? await session.service.testResultDetails(result, for: session.patientID)
        }
    }
}

// MARK: - Detail

struct TestResultDetailView: View {
    @Environment(Session.self) private var session
    /// Starts as the list's summary and is replaced once details load.
    @State private var result: TestResult
    @State private var showsAdditionalInfo = true
    @State private var openDocument: ResultDocument?

    init(result: TestResult) {
        _result = State(initialValue: result)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                resultsSection
                ResultTrendsSection(result: result)
                if !result.comments.isEmpty { commentsSection }
                if !result.documents.isEmpty { documentsSection }
                additionalInfoSection
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Test Details")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $openDocument) { DocumentPreviewSheet(document: $0, result: result) }
        .task(id: result.id) {
            // Keep the summary on screen if the details can't be fetched.
            if let detailed = try? await session.service.testResultDetails(result, for: session.patientID) {
                result = detailed
            }
        }
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(result.kind == .imaging ? "Imaging" : result.kind == .pathology ? "Pathology" : "Lab test",
                  systemImage: result.systemImage)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.brand)
                .textCase(.uppercase)
            Text(result.name)
                .font(.system(.title, design: .rounded).bold())
                .foregroundStyle(Theme.ink)
            Text("Collected \(result.date.dateAndTime)")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            statusChip
        }
    }

    /// Only for results with a normal range; a culture or X-ray has nothing
    /// to be "within".
    @ViewBuilder
    private var statusChip: some View {
        if let status = result.rangeStatus {
            RangeStatusPill(status: status)
        }
    }

    // MARK: Results

    private enum ResultRow: Identifiable {
        case component(ResultComponent)
        /// Every organism in the culture, keyed by its component's id.
        case culture([(id: String, organism: CultureOrganism)])

        var id: String {
            switch self {
            case .component(let component): component.id
            case .culture: "culture"
            }
        }
    }

    /// Components in order, with a culture's organism lines gathered into one
    /// row where the first of them appears. The lab's "Comment" lines go
    /// last: they explain the results (e.g. susceptibility notes on the
    /// organisms), but the portal sends them before the culture.
    private var resultRows: [ResultRow] {
        let organisms = result.components.compactMap { component in
            component.organism.map { (id: component.id, organism: $0) }
        }
        var rows: [ResultRow] = []
        var comments: [ResultRow] = []
        for component in result.components {
            if component.organism != nil {
                if !rows.contains(where: { $0.id == "culture" }) { rows.append(.culture(organisms)) }
            } else if component.name.localizedCaseInsensitiveCompare("Comment") == .orderedSame {
                comments.append(.component(component))
            } else {
                rows.append(.component(component))
            }
        }
        return rows + comments
    }

    private var resultsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("Results")
            if result.components.isEmpty {
                card {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Report").font(.headline)
                        if let summary = result.summary {
                            // Monospaced to match how the portal typesets reports.
                            Text(summary)
                                .font(.subheadline.monospaced())
                                .foregroundStyle(.secondary)
                        } else {
                            Text(result.documents.isEmpty
                                 ? "The report for this test isn't available in the app yet. You can view it on the MyRCHPortal website."
                                 : "Results for this test are available in the attached documents.")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                ForEach(resultRows) { row in
                    switch row {
                    case .component(let component):
                        card { ResultComponentView(component: component) }
                    case .culture(let organisms):
                        card { CultureView(organisms: organisms) }
                    }
                }
            }
        }
    }

    // MARK: Comments

    private var commentsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("Comments from your care team")
            ForEach(result.comments) { comment in
                card {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .firstTextBaseline) {
                            Label(comment.author, systemImage: "person.crop.circle.fill")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Theme.brand)
                            Spacer()
                            if let date = comment.date {
                                Text(date.mediumDate)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Text(comment.text)
                            .foregroundStyle(.primary)
                    }
                }
                .accessibilityElement(children: .combine)
            }
        }
    }

    // MARK: Documents

    private var documentsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("Documents")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(result.documents) { document in
                        Button { openDocument = document } label: {
                            DocumentThumbnail(document: document)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    // MARK: Additional information

    private var additionalInfoSection: some View {
        card {
            DisclosureGroup(isExpanded: $showsAdditionalInfo) {
                VStack(alignment: .leading, spacing: 14) {
                    infoRow("Ordering clinician", result.orderingProvider)
                    if let clinician = result.authorisingClinician {
                        infoRow("Authorising clinician", clinician)
                    }
                    infoRow("Collection date", result.date.dateAndTime)
                    if let specimen = result.specimen { infoRow("Specimen", specimen) }
                    if let resultDate = result.resultDate { infoRow("Result date", resultDate.dateAndTime) }
                    infoRow("Result status", result.status)
                    if let lab = result.resultingLab { infoRow("Resulting lab", lab) }
                }
                .padding(.top, 14)
            } label: {
                Text("Additional information")
                    .font(.headline)
                    .foregroundStyle(Theme.ink)
            }
            .tint(Theme.brand)
        }
    }

    // MARK: Building blocks

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.title3.bold())
            .foregroundStyle(Theme.ink)
    }

    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: Theme.cardRadius))
    }

    private func infoRow(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Result component + range graph

private struct ResultComponentView: View {
    let component: ResultComponent

    private var valueText: String {
        if let text = component.valueText { return text }
        return component.value?.formatted(.number.precision(.fractionLength(0...2))) ?? "—"
    }

    private var rangeText: String? {
        switch (component.normalLow, component.normalHigh) {
        case let (low?, high?): "\(low.formatted()) – \(high.formatted()) \(component.unit)"
        case let (nil, high?): "Below \(high.formatted()) \(component.unit)"
        case let (low?, nil): "Above \(low.formatted()) \(component.unit)"
        default: component.rangeText
        }
    }

    /// Plain-text findings ("No microscopy performed.") read as a sentence
    /// under the name, in body colour. Only measurements (a unit or a range,
    /// e.g. ">500 ug/g") sit beside the name in the in/out-of-range colour.
    private var isNarrative: Bool {
        guard component.value == nil, component.valueText != nil else { return false }
        return component.unit.isEmpty && rangeText == nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if isNarrative {
                VStack(alignment: .leading, spacing: 6) {
                    Text(component.name).font(.headline)
                    Text(valueText)
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                }
            } else {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(component.name).font(.headline)
                        if let rangeText {
                            Text("Normal range: \(rangeText)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    Text("\(valueText) \(component.unit)")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(component.isAbnormal ? Theme.orange : Theme.green)
                }
            }
            if let value = component.value, component.normalLow != nil || component.normalHigh != nil,
               (component.normalLow ?? -.infinity) < (component.normalHigh ?? .infinity) {
                RangeGraph(value: value, low: component.normalLow, high: component.normalHigh,
                           isAbnormal: component.isAbnormal, valueText: valueText)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(component.name), \(valueText) \(component.unit)")
        .accessibilityValue(component.isAbnormal ? "Outside normal range, \(rangeText ?? "")"
                                                 : "Within normal range, \(rangeText ?? "")")
    }
}

// MARK: - Culture

/// The organisms a culture grew, each with its colony count on a meter.
private struct CultureView: View {
    let organisms: [(id: String, organism: CultureOrganism)]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text("Culture").font(.headline)
                Spacer()
                Text("Colony count")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ForEach(Array(organisms.enumerated()), id: \.element.id) { index, entry in
                if index > 0 { Divider() }
                OrganismRow(organism: entry.organism)
            }
        }
    }
}

struct OrganismRow: View {
    let organism: CultureOrganism

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Text(organism.name)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
            VStack(alignment: .trailing, spacing: 4) {
                if let growth = organism.growth {
                    GrowthMeter(growth: growth)
                }
                // The lab's own word ("profuse", not our "heavy"), always
                // written out so the meter's shading is never the only cue.
                Text(growthLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(organism.name)
        .accessibilityValue(organism.growth.map { "\(growthLabel) growth, \($0.rawValue) of \(CultureOrganism.Growth.allCases.count)" }
                            ?? growthLabel)
    }

    /// Only the first letter is raised, so units like "CFU/mL" survive.
    private var growthLabel: String {
        guard let text = organism.growthText, let first = text.first else {
            return organism.growth?.label ?? "Count not reported"
        }
        return first.uppercased() + text.dropFirst()
    }
}

/// Four segments, scant → heavy, filled up to the level. One hue deepening
/// with each step, since colony count is an amount, not a good/bad status.
struct GrowthMeter: View {
    let growth: CultureOrganism.Growth

    /// Brand-teal strength per step; reads as "more" in light and dark mode.
    private static let stepOpacity: [Double] = [0.35, 0.55, 0.78, 1.0]

    var body: some View {
        HStack(spacing: 2) {
            ForEach(CultureOrganism.Growth.allCases, id: \.self) { step in
                RoundedRectangle(cornerRadius: 3)
                    .fill(step <= growth
                          ? Theme.brand.opacity(Self.stepOpacity[step.rawValue - 1])
                          : Color(.tertiarySystemFill))
                    .frame(width: 18, height: 8)
            }
        }
    }
}

/// A horizontal range bar: green across the normal range, yellow→orange
/// outside it, with a marker bubble showing where the value falls. Handles
/// one-sided ranges too: "<5" is green from zero to 5, ">200" from 200 on.
private struct RangeGraph: View {
    let value: Double
    let low: Double?
    let high: Double?
    let isAbnormal: Bool
    let valueText: String

    private let barY: CGFloat = 58
    private let barHeight: CGFloat = 12
    /// Measured, since the bubble's width depends on the value's text.
    @State private var bubbleWidth: CGFloat = 56

    /// Visible domain: the normal range padded on each side, widened to fit
    /// the value. An open side starts at zero ("<5") or runs well past the
    /// bound (">200"), since lab values are rarely negative.
    private var domain: ClosedRange<Double> {
        switch (low, high) {
        case let (low?, high?):
            let span = high - low
            return min(low - span * 0.5, value - span * 0.1)...max(high + span * 0.5, value + span * 0.1)
        case let (nil, high?):
            return min(0, value)...max(high * 1.6, value * 1.15)
        case let (low?, nil):
            return min(max(0, low * 0.4), value * 0.85)...max(low * 1.8, value * 1.15)
        case (nil, nil):
            return (value - 1)...(value + 1)
        }
    }

    /// The green span, clamped to the domain on an open side.
    private var normalSpan: ClosedRange<Double> {
        (low ?? domain.lowerBound)...(high ?? domain.upperBound)
    }

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let x = { (v: Double) -> CGFloat in
                CGFloat((v - domain.lowerBound) / (domain.upperBound - domain.lowerBound)) * width
            }
            // The bubble slides to stay on screen; the arrow tracks the value
            // but is kept under the bubble's straight edge (clear of its
            // rounded ends), so the two always read as one marker.
            let half = bubbleWidth / 2
            let markerX = min(max(x(value), half), width - half)
            let arrowInset = min(12, half)
            let arrowX = min(max(x(value), markerX - half + arrowInset), markerX + half - arrowInset)
            let markerColor = isAbnormal ? Theme.orange : Theme.green

            ZStack {
                // Out-of-range track with the normal range over it, clipped
                // together so a range reaching an end keeps the round cap.
                ZStack(alignment: .leading) {
                    LinearGradient(colors: [Theme.orange, Theme.yellow, Theme.yellow, Theme.orange],
                                   startPoint: .leading, endPoint: .trailing)
                    Rectangle()
                        .fill(Theme.green)
                        .frame(width: x(normalSpan.upperBound) - x(normalSpan.lowerBound))
                        .offset(x: x(normalSpan.lowerBound))
                }
                .frame(width: width, height: barHeight)
                .clipShape(.capsule)
                .position(x: width / 2, y: barY)

                // Value bubble + pointer.
                Text(valueText)
                    .font(.subheadline.bold())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(markerColor, in: .capsule)
                    .fixedSize()
                    .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { bubbleWidth = $0 }
                    .position(x: markerX, y: 18)
                Image(systemName: "arrowtriangle.down.fill")
                    .font(.caption)
                    .foregroundStyle(markerColor)
                    .position(x: arrowX, y: 40)

                // Range bound labels, for the sides that have one.
                if let low {
                    Text(low.formatted())
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .position(x: x(low), y: barY + 22)
                }
                if let high {
                    Text(high.formatted())
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .position(x: x(high), y: barY + 22)
                }
            }
        }
        .frame(height: 88)
        .accessibilityHidden(true)
    }
}

// MARK: - Documents

private struct DocumentThumbnail: View {
    let document: ResultDocument

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "doc.text.fill")
                .font(.system(size: 34))
                .foregroundStyle(Theme.brand)
                .frame(width: 120, height: 92)
                .background(Theme.brand.opacity(0.1), in: .rect(cornerRadius: 14))
            VStack(spacing: 2) {
                Text(document.title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Theme.ink)
                Text(document.pageCount.map { "\($0) page\($0 == 1 ? "" : "s")" } ?? "Tap to view")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: Theme.cardRadius))
    }
}

/// Downloads and shows a result's scan or report: PDFs in PDFKit, anything
/// else as an image. Mock documents (no download path) get placeholder pages.
private struct DocumentPreviewSheet: View {
    let document: ResultDocument
    let result: TestResult
    @Environment(\.dismiss) private var dismiss
    @Environment(Session.self) private var session

    private enum LoadState {
        case loading
        case pdf(PDFDocument)
        case image(UIImage)
        case failed(String)
    }
    @State private var state: LoadState = .loading

    var body: some View {
        NavigationStack {
            content
                .background(Color(.systemGroupedBackground))
                .navigationTitle(document.title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                    }
                }
        }
        .task(id: document.id) { await load() }
    }

    @ViewBuilder
    private var content: some View {
        if document.downloadPath == nil {
            ScrollView {
                VStack(spacing: 20) {
                    ForEach(1...(document.pageCount ?? 1), id: \.self) { page in
                        mockPage(page)
                    }
                }
                .padding()
            }
        } else {
            switch state {
            case .loading:
                ProgressView("Loading document…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .pdf(let pdf):
                PDFKitView(document: pdf)
                    .ignoresSafeArea(edges: .bottom)
            case .image(let image):
                ScrollView {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .accessibilityLabel(document.title)
                        .padding()
                }
            case .failed(let message):
                ContentUnavailableView {
                    Label("Couldn't open document", systemImage: "doc.questionmark")
                } description: {
                    Text(message)
                } actions: {
                    Button("Try again") { Task { await load() } }
                }
            }
        }
    }

    private func load() async {
        guard document.downloadPath != nil else { return }
        state = .loading
        do {
            let data = try await session.service.documentData(document, for: session.patientID)
            // Sniff the bytes rather than trust the file name or MIME type.
            if data.starts(with: Array("%PDF".utf8)), let pdf = PDFDocument(data: data) {
                state = .pdf(pdf)
            } else if let image = UIImage(data: data) {
                state = .image(image)
            } else {
                state = .failed("This document is in a format the app can't show yet.")
            }
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    private func mockPage(_ page: Int) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(result.name).font(.headline)
            Text("Collected \(result.date.dateAndTime)")
                .font(.caption)
                .foregroundStyle(.secondary)
            Divider()
            // Stand-in document body, redacted into grey lines.
            ForEach(0..<12, id: \.self) { line in
                Text(line % 3 == 2 ? "Placeholder line" : "Placeholder report line of text that fills the page width")
                    .font(.caption2)
                    .lineLimit(1)
                    .redacted(reason: .placeholder)
            }
            Spacer(minLength: 20)
            Text("Page \(page) of \(document.pageCount ?? 1)")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity)
        }
        .padding(24)
        .frame(maxWidth: .infinity, minHeight: 420, alignment: .top)
        .background(.white, in: .rect(cornerRadius: 6))
        .shadow(color: .black.opacity(0.08), radius: 10, y: 4)
    }
}

/// SwiftUI has no PDF view, so host PDFKit's.
private struct PDFKitView: UIViewRepresentable {
    let document: PDFDocument

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.backgroundColor = .systemGroupedBackground
        view.document = document
        return view
    }

    func updateUIView(_ view: PDFView, context: Context) {
        if view.document !== document { view.document = document }
    }
}
