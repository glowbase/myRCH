import SwiftUI

/// Every section of the app as a grid of tiles, like the Health app's
/// Browse tab.
struct BrowseView: View {
    @State private var searchText = ""

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 2)

    private var features: [Feature] {
        guard !searchText.isEmpty else { return Feature.browsable }
        return Feature.browsable.filter { $0.title.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
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
        .overlay {
            if features.isEmpty {
                ContentUnavailableView.search(text: searchText)
            }
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Browse")
        .searchable(text: $searchText)
        .navigationDestination(for: Feature.self) { FeatureDestination(feature: $0) }
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
        case .trackHealth, .implants, .sharing:
            ContentUnavailableView(feature.title, systemImage: feature.systemImage,
                                   description: Text("This section is coming soon."))
                .navigationTitle(feature.title)
        }
    }
}
