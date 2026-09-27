import SwiftUI

/// A goal the family is working towards, kept on this iPhone per child.
/// (Goals shared with the care team live on the portal; see `PortalGoal`.)
struct HealthGoal: Identifiable, Codable, Hashable {
    var id = UUID()
    var text: String
    var created = Date.now
    var completed: Date?

    var isDone: Bool { completed != nil }
}

/// Goals for every child, stored as JSON in user defaults (small, and not
/// clinical data from the portal).
@Observable
final class GoalStore {
    private static let key = "healthGoals"
    private var byPatient: [String: [HealthGoal]]

    init() {
        let data = UserDefaults.standard.data(forKey: Self.key) ?? Data()
        byPatient = (try? JSONDecoder().decode([String: [HealthGoal]].self, from: data)) ?? [:]
    }

    func goals(for patientID: String) -> [HealthGoal] {
        // Open goals first, then finished ones, newest first within each.
        (byPatient[patientID] ?? []).sorted {
            $0.isDone != $1.isDone ? !$0.isDone : $0.created > $1.created
        }
    }

    func add(_ text: String, for patientID: String) {
        byPatient[patientID, default: []].append(HealthGoal(text: text))
        save()
    }

    func toggle(_ goal: HealthGoal, for patientID: String) {
        guard let index = byPatient[patientID]?.firstIndex(where: { $0.id == goal.id }) else { return }
        byPatient[patientID]?[index].completed = goal.isDone ? nil : .now
        save()
    }

    func delete(_ goal: HealthGoal, for patientID: String) {
        byPatient[patientID]?.removeAll { $0.id == goal.id }
        save()
    }

    private func save() {
        if let data = try? JSONEncoder().encode(byPatient) {
            UserDefaults.standard.set(data, forKey: Self.key)
        }
    }
}

/// Home's Health Goals, Health-style: goals shared with the care team on
/// the portal, then the family's own goals with tick circles and a progress
/// bar, and an Add Goal button.
struct HealthGoalsSection: View {
    @Environment(Session.self) private var session
    @State private var store = GoalStore()
    @State private var showsAdd = false
    @State private var portalGoals: [PortalGoal] = []
    @State private var portalLoaded = false
    @State private var shareError: String?

    /// Only the first goal's request has been captured (see the service).
    private var canShare: Bool { session.useLivePortal && portalLoaded && portalGoals.isEmpty }

    private let color = Color.green

    var body: some View {
        let goals = store.goals(for: session.patientID)
        let done = goals.filter(\.isDone).count
        VStack(alignment: .leading, spacing: 12) {
            SummarySectionHeader<Feature>(title: "Health Goals")
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Label("Goals", systemImage: "target")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(color)
                    Spacer()
                    if !goals.isEmpty {
                        Text("\(done) of \(goals.count) done")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                if !portalGoals.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Shared with the care team")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        ForEach(portalGoals) { goal in
                            HStack(alignment: .firstTextBaseline, spacing: 12) {
                                Image(systemName: "person.2.fill")
                                    .foregroundStyle(color)
                                    .frame(width: 24)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(goal.text)
                                    if let updated = goal.lastUpdated {
                                        Text("Updated \(updated)")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }
                    if !goals.isEmpty { Divider() }
                }

                if goals.isEmpty && portalGoals.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Set a goal")
                            .font(.system(.title3, design: .rounded).bold())
                        Text("Something to work towards, like sleeping through the night or using a spacer every time. Bring it up at the next visit.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } else if !goals.isEmpty {
                    if !portalGoals.isEmpty {
                        Text("On this iPhone")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    ProgressView(value: Double(done), total: Double(goals.count))
                        .tint(color)
                    VStack(spacing: 0) {
                        ForEach(Array(goals.enumerated()), id: \.element.id) { index, goal in
                            if index > 0 { Divider().padding(.leading, 36) }
                            row(goal)
                        }
                    }
                }

                Button {
                    showsAdd = true
                } label: {
                    Label("Add Goal", systemImage: "plus")
                        .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
                .tint(color)

                Text(session.useLivePortal
                     ? "Shared goals are on your child's portal record. Others are kept on this iPhone only."
                     : "Kept on this iPhone only. They aren't sent to the hospital.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(16)
            .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: Theme.cardRadius))
        }
        .sheet(isPresented: $showsAdd) {
            AddGoalSheet(canShare: canShare) { text, share in
                if share {
                    Task { await shareGoal(text) }
                } else {
                    store.add(text, for: session.patientID)
                }
            }
        }
        .alert("Couldn't share the goal", isPresented: .constant(shareError != nil)) {
            Button("OK") { shareError = nil }
        } message: {
            Text(shareError ?? "")
        }
        .task(id: session.patientID) { await loadPortalGoals() }
    }

    private func loadPortalGoals() async {
        portalGoals = (try? await session.service.patientGoals(for: session.patientID)) ?? []
        portalLoaded = true
    }

    /// If the portal refuses, or its reply can't be read, check whether the
    /// goal arrived anyway before falling back to keeping it on the iPhone.
    private func shareGoal(_ text: String) async {
        do {
            try await session.service.addPatientGoal(text, for: session.patientID)
            await loadPortalGoals()
        } catch {
            await loadPortalGoals()
            if !portalGoals.contains(where: { $0.text == text }) {
                store.add(text, for: session.patientID)
                shareError = "It's been saved on this iPhone instead. \(error.localizedDescription)"
            }
        }
    }

    private func row(_ goal: HealthGoal) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Button {
                withAnimation { store.toggle(goal, for: session.patientID) }
            } label: {
                Image(systemName: goal.isDone ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(goal.isDone ? color : Color.secondary)
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.plain)
            .sensoryFeedback(.success, trigger: goal.isDone) { _, done in done }
            .accessibilityLabel(goal.isDone ? "Mark as not done" : "Mark as done")

            VStack(alignment: .leading, spacing: 2) {
                Text(goal.text)
                    .strikethrough(goal.isDone, color: .secondary)
                    .foregroundStyle(goal.isDone ? .secondary : .primary)
                Text(goal.completed.map { "Done \($0.mediumDate)" } ?? "Added \(goal.created.mediumDate)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 8)
        .contextMenu {
            Button("Delete Goal", systemImage: "trash", role: .destructive) {
                withAnimation { store.delete(goal, for: session.patientID) }
            }
        }
    }
}

private struct AddGoalSheet: View {
    let canShare: Bool
    let onAdd: (_ text: String, _ share: Bool) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var share = true
    @FocusState private var focused: Bool

    private static let suggestions = [
        "Sleep through the night", "Use the spacer every time", "Drink more water",
        "Take medicine on time", "Try a new food each week"
    ]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("e.g. Sleep through the night", text: $text, axis: .vertical)
                        .lineLimit(2...4)
                        .focused($focused)
                } footer: {
                    if !canShare {
                        Text("Kept on this iPhone. Bring it up with the care team at the next visit.")
                    }
                }
                if canShare {
                    Section {
                        Toggle("Share with the care team", isOn: $share)
                    } footer: {
                        Text(share ? "Added to your child's record in My RCH Portal, where the care team can see it."
                                   : "Kept on this iPhone only.")
                    }
                }
                Section("Suggestions") {
                    ForEach(Self.suggestions, id: \.self) { suggestion in
                        Button(suggestion) { text = suggestion }
                    }
                }
            }
            .navigationTitle("New Goal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        onAdd(text.trimmingCharacters(in: .whitespacesAndNewlines), canShare && share)
                        dismiss()
                    }
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onAppear { focused = true }
        }
        .presentationDetents([.medium, .large])
    }
}
