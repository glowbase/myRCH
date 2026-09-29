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

/// The medicine, its strength and form, and when they started taking it.
/// The portal takes a single name, so the fields are joined into one
/// ("Zinc Acetate 1 mg Liquid") when it's sent.
private struct AddMedicationDetailsView: View {
    let patientID: String
    let initialName: String
    var onAdded: () -> Void

    @Environment(Session.self) private var session

    @State private var name = ""
    @State private var strength = ""
    @State private var unit = "mg"
    /// Empty when they're not sure.
    @State private var form = ""
    @State private var startDate = Date.now
    @State private var isSaving = false
    @State private var errorMessage: String?

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var trimmedStrength: String { strength.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// What's sent to the portal: name, then strength with its unit, then
    /// form, leaving out whatever wasn't filled in. "%" sits against the
    /// number ("6%"), as in the portal's own names.
    private var fullName: String {
        var parts = [trimmedName]
        if !trimmedStrength.isEmpty {
            parts.append(unit == "%" ? "\(trimmedStrength)%" : "\(trimmedStrength) \(unit)")
        }
        if !form.isEmpty { parts.append(form) }
        return parts.joined(separator: " ")
    }

    var body: some View {
        Form {
            Section("Medication") {
                TextField("Name", text: $name, axis: .vertical)
            }
            Section {
                HStack {
                    TextField("Strength, e.g. 1", text: $strength)
                        .keyboardType(.decimalPad)
                    Picker("Unit", selection: $unit) {
                        ForEach(Medication.strengthUnits, id: \.self) { Text($0) }
                    }
                    .labelsHidden()
                    .fixedSize()
                }
                Picker("Form", selection: $form) {
                    Text("Not sure").tag("")
                    ForEach(Medication.productForms, id: \.self) { Text($0) }
                }
            } header: {
                Text("Strength and Form")
            } footer: {
                Text("Optional. You'll find these on the box or bottle.")
            }
            if !trimmedName.isEmpty {
                Section("Will Be Added As") {
                    Text(fullName)
                }
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
            try await session.service.addMedication(named: fullName, startDate: startDate, for: patientID)
            onAdded()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
