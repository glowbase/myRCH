import SwiftUI

struct AllergiesView: View {
    let patientID: String
    @Environment(Session.self) private var session

    var body: some View {
        AsyncSection {
            try await session.service.allergies(for: patientID)
        } content: { allergies in
            List {
                ForEach(allergies) { allergy in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(allergy.substance).font(.headline)
                            Spacer()
                            Text(allergy.severity)
                                .font(.caption.bold())
                                .foregroundStyle(Theme.red)
                        }
                        Text("Reaction: \(allergy.reaction)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 2)
                }
            }
            .overlay {
                if allergies.isEmpty, !session.service.readsAllergies {
                    // Unknown isn't "none".
                    ContentUnavailableView("Allergies Not Available", systemImage: "allergens",
                                           description: Text(AllergyNotice.unavailable))
                } else if allergies.isEmpty {
                    ContentUnavailableView("No allergies on file", systemImage: "allergens",
                                           description: Text("Allergies the hospital has recorded appear here. Tell the care team about any that are missing."))
                }
            }
        }
        .navigationTitle("Allergies")
    }
}

struct ImmunisationsView: View {
    let patientID: String
    @Environment(Session.self) private var session

    var body: some View {
        AsyncSection {
            try await session.service.immunisations(for: patientID)
        } content: { shots in
            List {
                if let latest = shots.max(by: { $0.date < $1.date }),
                   let latestGroup = ImmunisationGroup.group(shots).first(where: { $0.name == latest.name }) {
                    Section {
                        SummaryCard(category: "Most Recent", systemImage: "syringe.fill",
                                    color: Feature.immunisations.tileArt.color,
                                    detail: latest.date.mediumDate) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(latest.name)
                                    .font(.system(.title3, design: .rounded).bold())
                                Text("\(ImmunisationGroup.group(shots).count) vaccines on file")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        // Hidden link: a visible one would add a second chevron.
                        .background {
                            NavigationLink {
                                ImmunisationDetailView(group: latestGroup, patientID: patientID)
                            } label: { EmptyView() }
                                .opacity(0)
                        }
                        .summaryCardRow()
                    }
                }
                ForEach(ImmunisationGroup.group(shots)) { group in
                    NavigationLink {
                        ImmunisationDetailView(group: group, patientID: patientID)
                    } label: {
                        HStack(spacing: 14) {
                            Image(systemName: "syringe.fill")
                                .font(.title3)
                                .foregroundStyle(Feature.immunisations.accent)
                                .frame(width: 40, height: 40)
                                .background(Feature.immunisations.accent.opacity(0.14), in: .circle)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(group.name).font(.headline)
                                Text(group.dates.count == 1
                                     ? group.dates[0].mediumDate
                                     : "\(group.dates.count) doses · latest \(group.dates.first?.mediumDate ?? "")")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
            .overlay {
                if shots.isEmpty {
                    ContentUnavailableView("No immunisations on file", systemImage: "syringe",
                                           description: Text("Vaccines recorded by the hospital appear here. Ones given by a GP or school program may not be listed."))
                }
            }
        }
        .navigationTitle("Immunisations")
    }
}

/// Immunisations of the same vaccine collapsed into one entry, newest dose first.
struct ImmunisationGroup: Identifiable, Hashable {
    var id: String { name }
    let name: String
    let dates: [Date]
    /// The portal's vaccine record, for loading dose details.
    var vaccineID: String? = nil

    static func group(_ shots: [Immunisation]) -> [ImmunisationGroup] {
        Dictionary(grouping: shots, by: \.name)
            .map { name, doses in
                ImmunisationGroup(name: name, dates: doses.map(\.date).sorted(by: >),
                                  vaccineID: doses.lazy.compactMap(\.vaccineID).first)
            }
            .sorted { ($0.dates.first ?? .distantPast) > ($1.dates.first ?? .distantPast) }
    }
}

/// Every dose of one vaccine, with whatever the portal recorded about each:
/// product, dose, route, site, where it was given and the batch number.
struct ImmunisationDetailView: View {
    let group: ImmunisationGroup
    let patientID: String
    @Environment(Session.self) private var session

    /// Nil until loaded. Falls back to the list's dates if details fail.
    @State private var doses: [ImmunisationDose]?
    @State private var showsExplanation = false

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    // Purple icon, grey words: the purple is too dim for small
                    // text on a dark background, though fine as an icon.
                    Label {
                        Text("Immunisation").foregroundStyle(.secondary)
                    } icon: {
                        Image(systemName: "syringe.fill").foregroundStyle(Feature.immunisations.accent)
                    }
                    .font(.caption.weight(.semibold))
                    .textCase(.uppercase)
                    Text(group.name)
                        .font(.system(.title2, design: .rounded).bold())
                    Text("\(group.dates.count) dose\(group.dates.count == 1 ? "" : "s") on record")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }

            if let doses {
                ForEach(doses) { dose in
                    Section(dose.date.mediumDate) {
                        doseRows(dose)
                    }
                }
            } else {
                Section {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .navigationTitle("Immunisation")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            AIExplainToolbarItem(title: "Explain Immunisation") { showsExplanation = true }
        }
        .sheet(isPresented: $showsExplanation) {
            ImmunisationExplanationSheet(group: group, doses: doses ?? [])
        }
        .task(id: group.vaccineID) { await load() }
    }

    @ViewBuilder
    private func doseRows(_ dose: ImmunisationDose) -> some View {
        let rows: [(String, String?)] = [
            ("Product", dose.productName),
            ("Dose", dose.dose),
            ("Route", dose.route),
            ("Site", dose.site),
            ("Given at", dose.location),
            ("Manufacturer", dose.manufacturer),
            ("Batch number", dose.lotNumber)
        ]
        let filled = rows.compactMap { label, value in value.map { (label, $0) } }
        if filled.isEmpty {
            Text("No further details recorded.")
                .foregroundStyle(.secondary)
        } else {
            ForEach(filled, id: \.0) { label, value in
                LabeledContent(label, value: value)
            }
        }
    }

    private func load() async {
        let fallback = group.dates.map { ImmunisationDose(date: $0) }
        guard let vaccineID = group.vaccineID else {
            doses = fallback
            return
        }
        let loaded = try? await session.service.immunisationDoses(vaccineID: vaccineID, for: patientID)
        // An empty or failed response still shows the dates we know about.
        doses = (loaded?.isEmpty == false) ? loaded : fallback
    }
}
