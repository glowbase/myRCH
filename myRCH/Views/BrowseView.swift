import SwiftUI

/// Every section of the app as a grid of tiles, like the Health app's
/// Browse tab. Searching also finds individual records (results, letters,
/// medication, visits, immunisations), as Health's search does.
struct BrowseView: View {
    @Environment(Session.self) private var session
    @State private var searchText = ""
    /// Loaded the first time a search starts; the service caches it.
    @State private var index: SearchIndex?

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 2)

    private var features: [Feature] {
        guard !searchText.isEmpty else { return Feature.browsable }
        return Feature.browsable.filter { $0.title.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        Group {
            if searchText.isEmpty {
                grid
            } else {
                SearchResultsList(query: searchText, features: features, index: index)
            }
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Browse")
        .searchable(text: $searchText, prompt: "Search sections and records")
        .navigationDestination(for: Feature.self) { FeatureDestination(feature: $0) }
        .task(id: searchText.isEmpty) {
            guard !searchText.isEmpty, index == nil else { return }
            index = await SearchIndex.load(service: session.service, patientID: session.patientID)
        }
        .onChange(of: session.patientID) { index = nil }
    }

    private var grid: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Quick Links")
                    .font(.title2.bold())
                    .padding(.horizontal, 4)
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(features) { feature in
                        NavigationLink(value: feature) {
                            BrowseTile(feature: feature)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding()
        }
    }
}

/// Records to search, fetched together when a search starts.
struct SearchIndex {
    var results: [TestResult] = []
    var letters: [Letter] = []
    var medications: [Medication] = []
    var appointments: [Appointment] = []
    var immunisations: [ImmunisationGroup] = []

    static func load(service: PortalService, patientID: String) async -> SearchIndex {
        async let results = try? service.testResults(for: patientID)
        async let letters = try? service.letters(for: patientID)
        async let medications = try? service.medications(for: patientID)
        async let appointments = try? service.appointments(for: patientID)
        async let immunisations = try? service.immunisations(for: patientID)
        return SearchIndex(results: (await results ?? []).sorted(by: TestResult.newestFirst),
                           letters: (await letters ?? []).sorted { $0.date > $1.date },
                           medications: await medications ?? [],
                           appointments: (await appointments ?? []).sorted { $0.date > $1.date },
                           immunisations: ImmunisationGroup.group(await immunisations ?? []))
    }
}

/// Matches grouped by kind, each opening the record itself.
private struct SearchResultsList: View {
    let query: String
    let features: [Feature]
    let index: SearchIndex?
    @Environment(Session.self) private var session

    private func has(_ fields: String?...) -> Bool {
        fields.contains { $0?.localizedCaseInsensitiveContains(query) ?? false }
    }

    var body: some View {
        let results = index?.results.filter { has($0.name, $0.orderingProvider) } ?? []
        let letters = index?.letters.filter { has($0.title, $0.author) } ?? []
        let medications = index?.medications.filter { has($0.name, $0.commonName) } ?? []
        let visits = index?.appointments.filter { has($0.title, $0.department, $0.provider) } ?? []
        let immunisations = index?.immunisations.filter { has($0.name) } ?? []
        let nothing = features.isEmpty && results.isEmpty && letters.isEmpty && medications.isEmpty
            && visits.isEmpty && immunisations.isEmpty

        List {
            if !features.isEmpty {
                Section("Sections") {
                    ForEach(features) { feature in
                        NavigationLink(value: feature) {
                            row(feature.title, detail: nil, art: feature.tileArt)
                        }
                    }
                }
            }
            if !results.isEmpty {
                Section("Test Results") {
                    ForEach(results.prefix(8)) { result in
                        NavigationLink { TestResultDetailView(result: result) } label: {
                            row(result.name, detail: result.date.mediumDate, art: Feature.testResults.tileArt)
                        }
                    }
                }
            }
            if !letters.isEmpty {
                Section("Letters") {
                    ForEach(letters.prefix(8)) { letter in
                        NavigationLink {
                            PortalDocumentView(title: letter.title, id: letter.id,
                                               shareName: "\(letter.title) – \(letter.date.mediumDate)") {
                                try await session.service.letterHTML(letter, for: session.patientID)
                            }
                        } label: {
                            row(letter.title, detail: [letter.author, letter.date.mediumDate].compactMap { $0 }
                                .joined(separator: " · "), art: Feature.letters.tileArt)
                        }
                    }
                }
            }
            if !medications.isEmpty {
                Section("Medication") {
                    ForEach(medications.prefix(8)) { medication in
                        NavigationLink { MedicationDetailView(medication: medication) } label: {
                            row(medication.name, detail: medication.isActive ? medication.dose : "No longer taking",
                                art: Feature.medication.tileArt)
                        }
                    }
                }
            }
            if !visits.isEmpty {
                Section("Visits") {
                    ForEach(visits.prefix(8)) { visit in
                        NavigationLink { AppointmentDetailView(appointment: visit) } label: {
                            row(visit.title, detail: "\(visit.department) · \(visit.date.mediumDate)",
                                art: Feature.visits.tileArt)
                        }
                    }
                }
            }
            if !immunisations.isEmpty {
                Section("Immunisations") {
                    ForEach(immunisations.prefix(8)) { group in
                        NavigationLink {
                            ImmunisationDetailView(group: group, patientID: session.patientID)
                        } label: {
                            row(group.name, detail: group.dates.first?.mediumDate,
                                art: Feature.immunisations.tileArt)
                        }
                    }
                }
            }
            if index == nil {
                Section {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("Searching records…").foregroundStyle(.secondary)
                    }
                }
            }
        }
        .overlay {
            if nothing, index != nil {
                ContentUnavailableView.search(text: query)
            }
        }
    }

    private func row(_ title: String, detail: String?, art: (symbol: String, color: Color)) -> some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                if let detail, !detail.isEmpty {
                    Text(detail).font(.subheadline).foregroundStyle(.secondary)
                }
            }
        } icon: {
            Image(systemName: art.symbol).foregroundStyle(art.color)
        }
    }
}

/// Icon in the section's colour above its name, on a rounded card.
private struct BrowseTile: View {
    let feature: Feature

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: feature.tileArt.symbol)
                .foregroundStyle(feature.tileArt.color)
                .font(.system(size: 30))
                .frame(height: 36, alignment: .leading)
            Text(feature.title)
                .font(.headline)
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: Theme.cardRadius))
        .contentShape(.rect(cornerRadius: Theme.cardRadius))
    }
}

/// The screen for a section, shared by Browse and the dashboard's links.
struct FeatureDestination: View {
    let feature: Feature
    @Environment(Session.self) private var session

    /// What the section will do, so "coming soon" still tells you something.
    private var comingSoonText: String {
        switch feature {
        case .trackHealth: "Record symptoms, measurements and notes to share with the care team. Coming in a future update."
        case .implants: "Devices and implants on the hospital record, with their details. Coming in a future update."
        default: "This section is coming soon."
        }
    }

    var body: some View {
        switch feature {
        case .visits: AppointmentsView(patientID: session.patientID)
        case .testResults: TestResultsView(patientID: session.patientID)
        case .medication: MedicationsView(patientID: session.patientID)
        case .immunisations: ImmunisationsView(patientID: session.patientID)
        case .allergies: AllergiesView(patientID: session.patientID)
        case .healthSummary: HealthSummaryView(patientID: session.patientID)
        case .messages: MessagesView(patientID: session.patientID)
        case .growthCharts: GrowthChartsView(patientID: session.patientID)
        case .letters: LettersView(patientID: session.patientID)
        case .medicalID: MedicalIDView(patientID: session.patientID)
        case .sharing: ShareSummaryView(patientID: session.patientID)
        case .trackHealth, .implants:
            ContentUnavailableView(feature.title, systemImage: feature.systemImage,
                                   description: Text(comingSoonText))
                .navigationTitle(feature.title)
        }
    }
}
