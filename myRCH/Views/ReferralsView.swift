import SwiftUI
import UIKit

/// Referrals on the child's record: who they were referred to, by whom, and
/// their status. Open referrals come first, then closed ones, each newest
/// first.
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

/// Everything the portal lists about one referral, laid out like a visit:
/// what it's for as the title, with its status and requested date as chips,
/// then cards for who referred and who it's to. The list's copy shows
/// straight away; the service, departments and addresses load after.
struct ReferralDetailView: View {
    let referral: Referral
    @Environment(Session.self) private var session
    @Environment(\.openURL) private var openURL
    @State private var details: ReferralDetails?
    @State private var detailsError: String?
    @State private var copiedNumber = false

    private var isLoadingDetails: Bool { details == nil && detailsError == nil }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                if referral.status.isClosed {
                    closedNote
                }
                partyCard("Referred By", details?.referredBy, fallbackProvider: referral.referredBy)
                partyCard("Referred To", details?.referredTo, fallbackProvider: referral.referredTo,
                          fallbackFacility: referral.facility)
                if let detailsError {
                    Label("Couldn’t load the departments and addresses. \(detailsError)",
                          systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                informationCard
            }
            .padding()
            .animation(.default, value: details)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Referral")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: referral.id) {
            await loadDetails()
        }
        .refreshable {
            await loadDetails()
        }
    }

    // MARK: Header

    /// What it's for, from the details. Until they load, a placeholder of
    /// about the right length; if they fail, who it's to.
    private var title: String {
        if let service = details?.services.first { return service }
        return isLoadingDetails ? "Referral to outpatient clinic" : "Referral to \(referral.title)"
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Referral", systemImage: Feature.referrals.systemImage)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Feature.referrals.accent)
                .textCase(.uppercase)
            Text(title)
                .font(.system(.title, design: .rounded).bold())
                .foregroundStyle(Theme.ink)
                .redacted(reason: isLoadingDetails ? .placeholder : [])
            ChipRow {
                ReferralStatusChip(status: referral.status)
                if let requested = referral.requestedDescription {
                    CategoryChip(title: requested, systemImage: "calendar", color: Feature.referrals.accent)
                }
            }
            .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var closedNote: some View {
        card {
            Label("This referral has ended. If more care is needed, a new referral may be required.",
                  systemImage: "info.circle.fill")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: From and to

    /// The clinician, then their department and facility, address and
    /// phone. Before the details load, only the list's name and facility.
    private func partyCard(_ title: String, _ party: ReferralDetails.Party?,
                           fallbackProvider: String, fallbackFacility: String = "") -> some View {
        let provider = party.map { $0.provider.isEmpty ? fallbackProvider : $0.provider } ?? fallbackProvider
        let place = (party.map { [$0.department, $0.departmentSpecialty, $0.facility] } ?? [fallbackFacility])
            .filter { !$0.isEmpty }
        return VStack(alignment: .leading, spacing: 8) {
            sectionTitle(title)
            card {
                VStack(alignment: .leading, spacing: 14) {
                    if !provider.isEmpty {
                        iconRow("person.fill", title: provider, detail: party?.providerSpecialty)
                    }
                    if let first = place.first {
                        iconRow("building.2.fill", title: first,
                                detail: place.dropFirst().joined(separator: "\n"))
                    }
                    if let party, let firstLine = party.address.first {
                        Button {
                            openInMaps(party.address)
                        } label: {
                            iconRow("mappin.and.ellipse", title: firstLine,
                                    detail: party.address.dropFirst().joined(separator: "\n"),
                                    showsChevron: true)
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("Opens in Maps")
                    }
                    if let party, !party.phone.isEmpty,
                       let url = URL(string: "tel:\(party.phone.filter { $0.isNumber || $0 == "+" })") {
                        Link(destination: url) {
                            iconRow("phone.fill", title: party.phone, detail: nil, showsChevron: true)
                        }
                        .buttonStyle(.plain)
                    }
                    if party == nil, isLoadingDetails {
                        iconRow("building.2.fill", title: "Department name", detail: "Facility name")
                            .redacted(reason: .placeholder)
                    }
                }
            }
        }
    }

    // MARK: Additional information

    private var informationCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("Additional Information")
            card {
                VStack(alignment: .leading, spacing: 12) {
                    if let details {
                        // The first service is the title; any others are listed.
                        ForEach(details.services.dropFirst(), id: \.self) { service in
                            infoRow("Also For", service)
                        }
                        if !details.type.isEmpty {
                            infoRow("Referral Type", details.type)
                        }
                    }
                    if let created = referral.created {
                        infoRow("Created", created.mediumDate)
                    }
                    if !referral.number.isEmpty {
                        HStack(alignment: .center) {
                            infoRow("Referral Number", referral.number)
                            Button {
                                UIPasteboard.general.string = referral.number
                                copiedNumber = true
                            } label: {
                                Label(copiedNumber ? "Copied" : "Copy",
                                      systemImage: copiedNumber ? "checkmark" : "doc.on.doc")
                                    .font(.subheadline.weight(.semibold))
                            }
                            .buttonStyle(.bordered)
                            .buttonBorderShape(.capsule)
                            .tint(Feature.referrals.accent)
                            .sensoryFeedback(.success, trigger: copiedNumber) { _, copied in copied }
                        }
                        Text("Quote the referral number if you call the hospital about it.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    // MARK: Building blocks

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.title3.bold())
            .padding(.horizontal, 4)
    }

    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: Theme.cardRadius))
    }

    private func iconRow(_ systemImage: String, title: String, detail: String?,
                         showsChevron: Bool = false) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: systemImage)
                .foregroundStyle(Feature.referrals.accent)
                .frame(width: 40, height: 40)
                .background(Feature.referrals.accent.opacity(0.14), in: .circle)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body.weight(.semibold))
                if let detail, !detail.isEmpty {
                    Text(detail)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(minHeight: 40)
            Spacer(minLength: 0)
            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .frame(minHeight: 40)
            }
        }
        .contentShape(.rect)
    }

    private func infoRow(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(value)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private func openInMaps(_ address: [String]) {
        var components = URLComponents(string: "https://maps.apple.com/")
        components?.queryItems = [URLQueryItem(name: "q", value: address.joined(separator: ", "))]
        if let url = components?.url { openURL(url) }
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

/// The status in a list row: the portal's own wording, green while
/// authorised, grey once closed, and blue for anything else.
struct ReferralStatusPill: View {
    let status: Referral.Status

    var body: some View {
        Pill(text: status.title, tint: status.tint)
    }
}

/// The status as a chip under a referral's title, matching a visit's.
struct ReferralStatusChip: View {
    let status: Referral.Status

    var body: some View {
        CategoryChip(title: status.title, systemImage: status.systemImage, color: status.tint)
    }
}

extension Referral.Status {
    var tint: Color {
        switch code {
        case "1": Theme.green
        case "6": .secondary
        default: Theme.blue
        }
    }

    var systemImage: String {
        switch code {
        case "1": "checkmark.circle.fill"
        case "6": "archivebox.fill"
        default: "clock.fill"
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

    /// The portal's "Requested after 12/8/2026", as "Requested 12 Aug 2026",
    /// "Requested before 17 Feb 2026" or "Requested 17 Nov 2025 –
    /// 17 Feb 2026".
    var requestedDescription: String? {
        switch (requestedAfter, requestedBefore) {
        case let (after?, before?): "Requested \(after.mediumDate) – \(before.mediumDate)"
        case let (after?, nil): "Requested \(after.mediumDate)"
        case let (nil, before?): "Requested before \(before.mediumDate)"
        case (nil, nil): nil
        }
    }
}
