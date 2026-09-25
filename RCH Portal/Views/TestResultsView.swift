import SwiftUI

struct TestResultsView: View {
    let patientID: String
    @Environment(Session.self) private var session
    @State private var searchText = ""

    var body: some View {
        AsyncSection {
            try await session.service.testResults(for: patientID)
        } content: { results in
            let filtered = searchText.isEmpty ? results : results.filter {
                $0.name.localizedCaseInsensitiveContains(searchText)
            }
            List {
                Section {
                    ForEach(filtered) { result in
                        NavigationLink {
                            TestResultDetailView(result: result)
                        } label: {
                            TestResultRow(result: result)
                        }
                    }
                } header: {
                    Text("Showing \(filtered.count) of \(results.count)")
                }
            }
            .searchable(text: $searchText, prompt: "Search test results")
            .overlay {
                if filtered.isEmpty {
                    ContentUnavailableView.search(text: searchText)
                }
            }
        }
        .navigationTitle("Test Results")
    }
}

struct TestResultRow: View {
    let result: TestResult

    private var icon: String {
        switch result.kind {
        case .lab: "testtube.2"
        case .imaging: "xray"
        case .pathology: "microbe"
        }
    }

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(Theme.brand)
                .frame(width: 30)
            VStack(alignment: .leading, spacing: 3) {
                Text(result.name).font(.headline)
                Text(result.date.mediumDate)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(result.orderingProvider)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            Spacer()
            if result.isUnread {
                Circle().fill(Theme.brand).frame(width: 10, height: 10)
            }
        }
        .padding(.vertical, 4)
    }
}

struct TestResultDetailView: View {
    let result: TestResult

    var body: some View {
        List {
            Section {
                LabeledContent("Test", value: result.name)
                LabeledContent("Date", value: result.date.mediumDate)
                LabeledContent("Ordered by", value: result.orderingProvider)
            }
            if let summary = result.summary {
                Section("Result") { Text(summary) }
            } else {
                Section {
                    Text("Detailed results are not available in this preview.")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle(result.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}
