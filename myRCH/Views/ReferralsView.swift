import SwiftUI

/// Referrals on the child's record: who they were referred to, by whom, and
/// when it was requested for. Open referrals come first, then
/// closed ones, each newest first.
struct ReferralsView: View {
    let patientID: String
    @Environment(Session.self) private var session

    var body: some View {
        AsyncSection {
            try await session.service.referrals(for: patientID)
        } content: { referrals in
            let open = referrals.filter { !$0.status.isClosed }
            let closed = referrals.filter(\.status.isClosed)
            List {
                if !open.isEmpty {
                    Section("Open") {
                        ForEach(open) { referral in
                            link(referral)
                        }
                    }
                }
                if !closed.isEmpty {
                    Section("Closed") {
                        ForEach(closed) { referral in
                            link(referral)
                        }
                    }
                }
            }
            .overlay {
                if referrals.isEmpty {
                    ContentUnavailableView("No referrals", systemImage: Feature.referrals.systemImage,
                                           description: Text("Referrals to the hospital's clinics and services will appear here."))
                }
            }
        }
        .navigationTitle("Referrals")
    }

    private func link(_ referral: Referral) -> some View {
        NavigationLink {
            ReferralDetailView(referral: referral)
        } label: {
            ReferralRow(referral: referral)
        }
    }
}

struct ReferralRow: View {
    let referral: Referral

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: Feature.referrals.systemImage)
                .font(.title3)
                .foregroundStyle(Feature.referrals.accent)
                .frame(width: 40, height: 40)
                .background(Feature.referrals.accent.opacity(0.14), in: .circle)
            VStack(alignment: .leading, spacing: 3) {
                Text(referral.title)
                    .font(.headline)
                if let subtitle = referral.subtitle {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            ReferralStatusPill(status: referral.status)
        }
        .padding(.vertical, 4)
    }
}

/// Everything the portal lists about one referral. The list's copy shows
/// straight away; where it's from and to, and what it's for, load after.
struct ReferralDetailView: View {
    let referral: Referral
    @Environment(Session.self) private var session
    @State private var details: ReferralDetails?
    @State private var detailsError: String?

    var body: some View {
        List {
            Section {
                LabeledContent("Status") {
                    ReferralStatusPill(status: referral.status)
                }
                if let requested = referral.requested {
                    LabeledContent("Requested", value: requested)
                }
            } footer: {
                if referral.status.isClosed {
                    Text("This referral has ended. If more care is needed, a new referral may be required.")
                }
            }

            if let details {
                partySection("Referred By", details.referredBy, fallbackProvider: referral.referredBy)
                partySection("Referred To", details.referredTo, fallbackProvider: referral.referredTo)
            } else {
                Section("Referred By") {
                    partyPlaceholder(referral.referredBy)
                }
                Section {
                    partyPlaceholder(referral.referredTo)
                    if !referral.facility.isEmpty {
                        Label(referral.facility, systemImage: "building.2.fill")
                    }
                } header: {
                    Text("Referred To")
                } footer: {
                    if let detailsError {
                        Text("Couldn’t load the departments and addresses. \(detailsError)")
                    }
                }
            }

            Section {
                if let details {
                    ForEach(details.services, id: \.self) { service in
                        LabeledContent("Service", value: service)
                    }
                    if !details.type.isEmpty {
                        LabeledContent("Referral Type", value: details.type)
                    }
                }
                if !referral.number.isEmpty {
                    LabeledContent("Referral Number", value: referral.number)
                        .textSelection(.enabled)
                }
                if let created = referral.created {
                    LabeledContent("Created", value: created.mediumDate)
                }
            } header: {
                Text("Additional Information")
            } footer: {
                if !referral.number.isEmpty {
                    Text("Quote the referral number if you call the hospital about it.")
                }
            }
        }
        .navigationTitle("Referral to \(referral.title)")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: referral.id) {
            await loadDetails()
        }
        .refreshable {
            await loadDetails()
        }
    }

    /// The clinician, then their department and facility, address and phone.
    @ViewBuilder
    private func partySection(_ title: String, _ party: ReferralDetails.Party,
                              fallbackProvider: String) -> some View {
        let provider = party.provider.isEmpty ? fallbackProvider : party.provider
        let place = [party.department, party.departmentSpecialty, party.facility].filter { !$0.isEmpty }
        Section(title) {
            if !provider.isEmpty {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(provider)
                        if !party.providerSpecialty.isEmpty {
                            Text(party.providerSpecialty)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                } icon: {
                    Image(systemName: "person.fill")
                }
            }
            if !place.isEmpty {
                Label(place.joined(separator: "\n"), systemImage: "building.2.fill")
            }
            if !party.address.isEmpty {
                Label(party.address.joined(separator: "\n"), systemImage: "mappin.and.ellipse")
                    .textSelection(.enabled)
            }
            if !party.phone.isEmpty, let url = URL(string: "tel:\(party.phone.filter { $0.isNumber || $0 == "+" })") {
                Link(destination: url) {
                    Label(party.phone, systemImage: "phone.fill")
                }
            }
        }
    }

    @ViewBuilder
    private func partyPlaceholder(_ provider: String) -> some View {
        if !provider.isEmpty {
            Label(provider, systemImage: "person.fill")
        }
        if details == nil, detailsError == nil {
            ProgressView()
                .frame(maxWidth: .infinity)
        }
    }

    private func loadDetails() async {
        detailsError = nil
        do {
            details = try await session.service.referralDetails(referral, for: session.patientID)
        } catch {
            detailsError = error.localizedDescription
        }
    }
}

/// The portal's own wording for the status: green while authorised, grey
/// once closed, and blue for anything else.
struct ReferralStatusPill: View {
    let status: Referral.Status

    var body: some View {
        Pill(text: status.title, tint: tint)
    }

    private var tint: Color {
        switch status.code {
        case "1": Theme.green
        case "6": .secondary
        default: Theme.blue
        }
    }
}

extension Referral {
    /// Who it's to, or the facility when the portal doesn't name anyone.
    var title: String {
        if !referredTo.isEmpty { return referredTo }
        if !facility.isEmpty { return facility }
        return "Referral"
    }

    /// "From Sarah Flynn, Registrar · 3 Jul 2026"
    var subtitle: String? {
        let parts = [referredBy.isEmpty ? nil : "From \(referredBy)", created?.mediumDate].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// The portal's "Requested after 12/8/2026", as "After 12 Aug 2026",
    /// "Before 17 Feb 2026" or "17 Nov 2025 – 17 Feb 2026".
    var requested: String? {
        switch (requestedAfter, requestedBefore) {
        case let (after?, before?): "\(after.mediumDate) – \(before.mediumDate)"
        case let (after?, nil): "After \(after.mediumDate)"
        case let (nil, before?): "Before \(before.mediumDate)"
        case (nil, nil): nil
        }
    }
}
