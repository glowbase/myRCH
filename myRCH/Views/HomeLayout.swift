import SwiftUI

/// The sections Home can show. The order and which are pinned are chosen in
/// `EditHomeSheet`, like the Health app's Pinned list.
enum HomeSection: String, CaseIterable, Identifiable {
    case highlights, upcoming, results, medication, immunisations, growth, goals, sharing, explore

    var id: String { rawValue }

    var title: String {
        switch self {
        case .highlights: "Highlights"
        case .upcoming: "Upcoming Visits"
        case .results: "Recent Results"
        case .medication: "Medication"
        case .immunisations: "Immunisations"
        case .growth: "Growth"
        case .goals: "Health Goals"
        case .sharing: "Share My Record"
        case .explore: "Explore More"
        }
    }

    var art: (symbol: String, color: Color) {
        switch self {
        case .highlights: ("sparkles", .orange)
        case .upcoming: Feature.visits.tileArt
        case .results: Feature.testResults.tileArt
        case .medication: Feature.medication.tileArt
        case .immunisations: ("syringe.fill", Feature.immunisations.tileArt.color)
        case .growth: Feature.growthCharts.tileArt
        case .goals: ("target", .green)
        case .sharing: Feature.sharing.tileArt
        case .explore: ("lightbulb.max.fill", .yellow)
        }
    }

    /// A fresh install shows everything, in this order.
    static let defaultOrder: [HomeSection] = allCases
}

/// Which Home sections are pinned, in order. Stored as a comma-separated
/// list so it survives relaunches; sections added in later versions of the
/// app appear unpinned rather than disappearing.
struct HomeLayout {
    static let storageKey = "homeSections"

    var pinned: [HomeSection]

    init(stored: String) {
        if stored.isEmpty {
            pinned = HomeSection.defaultOrder
        } else {
            pinned = stored.split(separator: ",").compactMap { HomeSection(rawValue: String($0)) }
        }
    }

    var unpinned: [HomeSection] { HomeSection.allCases.filter { !pinned.contains($0) } }

    /// `"none"` keeps an empty choice distinct from the default (all).
    var stored: String { pinned.isEmpty ? "none" : pinned.map(\.rawValue).joined(separator: ",") }
}

/// Health-style editor: pinned sections can be dragged into order or
/// removed; the rest can be added back.
struct EditHomeSheet: View {
    @AppStorage(HomeLayout.storageKey) private var stored = ""
    @Environment(\.dismiss) private var dismiss

    private var layout: HomeLayout { HomeLayout(stored: stored) }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(layout.pinned) { section in
                        row(section)
                    }
                    .onMove { from, to in
                        var pinned = layout.pinned
                        pinned.move(fromOffsets: from, toOffset: to)
                        save(pinned)
                    }
                    .onDelete { offsets in
                        var pinned = layout.pinned
                        pinned.remove(atOffsets: offsets)
                        save(pinned)
                    }
                } header: {
                    Text("Pinned")
                } footer: {
                    Text("Drag to reorder. Pinned sections appear on Home in this order.")
                }

                if !layout.unpinned.isEmpty {
                    Section("More") {
                        ForEach(layout.unpinned) { section in
                            Button {
                                withAnimation { save(layout.pinned + [section]) }
                            } label: {
                                HStack {
                                    Image(systemName: "plus.circle.fill")
                                        .foregroundStyle(.green)
                                        .font(.title3)
                                    row(section)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                Section {
                    Button("Reset to Default") {
                        withAnimation { stored = "" }
                    }
                }
            }
            .environment(\.editMode, .constant(.active))
            .navigationTitle("Edit Home")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func row(_ section: HomeSection) -> some View {
        Label {
            Text(section.title)
        } icon: {
            Image(systemName: section.art.symbol)
                .foregroundStyle(section.art.color)
        }
    }

    /// The default layout is stored as "", so it follows future defaults.
    private func save(_ pinned: [HomeSection]) {
        stored = pinned == HomeSection.defaultOrder ? "" : HomeLayout(pinned: pinned).stored
    }
}

extension HomeLayout {
    init(pinned: [HomeSection]) { self.pinned = pinned }
}
