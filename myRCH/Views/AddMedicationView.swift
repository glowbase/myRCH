import SwiftUI

/// Searches the portal's medicine list to add one the hospital hasn't, such
/// as a supplement or something from the GP. If nothing matches, the name
/// can be added as typed. The care team reviews it at the next visit.
struct AddMedicationView: View {
    let patientID: String
    /// Called after the portal accepts the new medication.
    var onAdded: () -> Void

    @Environment(Session.self) private var session
    @Environment(\.dismiss) private var dismiss

    @State private var query = ""
    @State private var results: [MedicationSearchResult] = []
    @State private var isSearching = false
    @State private var searchFailed = false
    /// The name chosen from the results (or typed), shown in the details step.
    @State private var chosenName: String?

    private var trimmedQuery: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        NavigationStack {
            List {
                if !trimmedQuery.isEmpty {
                    Section {
                        Button {
                            chosenName = trimmedQuery
                        } label: {
                            Label("Add “\(trimmedQuery)”", systemImage: "plus.circle.fill")
                        }
                    } footer: {
                        Text("Can't find it? Add the name as you've typed it.")
                    }
                }
                if !results.isEmpty {
                    Section("Results") {
                        ForEach(results) { result in
                            Button {
                                chosenName = result.name
                            } label: {
                                Text(result.name)
                                    .foregroundStyle(.primary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                }
            }
            .overlay { overlay }
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always),
                        prompt: "Medicine name, e.g. Zinc")
            // Restarts on each keystroke, so the pause acts as a debounce.
            .task(id: trimmedQuery) { await search() }
            .navigationTitle("Add Medication")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .navigationDestination(item: $chosenName) { name in
                AddMedicationDetailsView(patientID: patientID, initialName: name) {
                    onAdded()
                    dismiss()
                }
            }
        }
    }

    @ViewBuilder
    private var overlay: some View {
        if trimmedQuery.count < 2 {
            ContentUnavailableView("Search Medicines", systemImage: "magnifyingglass",
                                   description: Text("Add medication the hospital hasn't, such as supplements or medicine from your GP."))
        } else if isSearching && results.isEmpty {
            ProgressView()
        } else if searchFailed && results.isEmpty {
            ContentUnavailableView("Couldn't Search", systemImage: "exclamationmark.triangle",
                                   description: Text("You can still add the name as typed."))
        }
    }

    private func search() async {
        let text = trimmedQuery
        guard text.count >= 2 else {
            results = []
            return
        }
        try? await Task.sleep(for: .milliseconds(350))
        guard !Task.isCancelled else { return }
        isSearching = true
        defer { isSearching = false }
        do {
            let found = try await session.service.searchMedications(text, for: patientID)
            guard !Task.isCancelled else { return }
            results = found
            searchFailed = false
        } catch {
            guard !Task.isCancelled else { return }
            results = []
            searchFailed = true
        }
    }
}

/// The name (editable, so strength and form can be added, e.g. "Zinc
/// Acetate 1 mg Liquid") and when they started taking it.
private struct AddMedicationDetailsView: View {
    let patientID: String
    let initialName: String
    var onAdded: () -> Void

    @Environment(Session.self) private var session

    @State private var name = ""
    @State private var startDate = Date.now
    @State private var isSaving = false
    @State private var errorMessage: String?

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        Form {
            Section {
                TextField("Name", text: $name, axis: .vertical)
            } header: {
                Text("Medication")
            } footer: {
                Text("Add the strength and form if you know them, e.g. “1 mg liquid”.")
            }
            Section {
                DatePicker("Started", selection: $startDate, in: ...Date.now, displayedComponents: .date)
            }
            Section {
                Label("The care team will review this at the next visit.", systemImage: "person.fill.checkmark")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Details")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                if isSaving {
                    ProgressView()
                } else {
                    Button("Add") { Task { await save() } }
                        .disabled(trimmedName.isEmpty)
                }
            }
        }
        .interactiveDismissDisabled(isSaving)
        .onAppear { if name.isEmpty { name = initialName } }
        .alert("Couldn't Add Medication", isPresented: .constant(errorMessage != nil)) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        do {
            try await session.service.addMedication(named: trimmedName, startDate: startDate, for: patientID)
            onAdded()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
