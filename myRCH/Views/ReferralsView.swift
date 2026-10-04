import SwiftUI

/// Referrals on the child's record: who they were referred to, by whom, and
/// for how long the referral is valid. Open referrals come first, then
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

/// Everything the portal lists about one referral.
struct ReferralDetailView: View {
    let referral: Referral

    var body: some View {
        List {
            Section {
                LabeledContent("Status") {
                    ReferralStatusPill(status: referral.status)
                }
                if let validity = referral.validity {
                    LabeledContent("Valid", value: validity)
                }
            } footer: {
                if referral.status.isClosed {
                    Text("This referral has ended. If more care is needed, a new referral may be required.")
                } else if let until = referral.validUntil, until < .now {
                    Text("This referral’s end date has passed.")
                }
            }

            Section {
                if !referral.referredTo.isEmpty {
                    LabeledContent("Referred To", value: referral.referredTo)
                }
                if !referral.facility.isEmpty {
                    LabeledContent("Facility", value: referral.facility)
                }
                if !referral.referredBy.isEmpty {
                    LabeledContent("Referred By", value: referral.referredBy)
                }
                if let created = referral.created {
                    LabeledContent("Created", value: created.mediumDate)
                }
            }

            if !referral.number.isEmpty {
                Section {
                    LabeledContent("Referral Number", value: referral.number)
                        .textSelection(.enabled)
                } footer: {
                    Text("Quote this number if you call the hospital about the referral.")
                }
            }
        }
        .navigationTitle(referral.title)
        .navigationBarTitleDisplayMode(.inline)
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

    /// "17 Nov 2025 – 17 Feb 2026", "From 12 Aug 2026" or "Until 17 Feb 2026".
    var validity: String? {
        switch (validFrom, validUntil) {
        case let (from?, until?): "\(from.mediumDate) – \(until.mediumDate)"
        case let (from?, nil): "From \(from.mediumDate)"
        case let (nil, until?): "Until \(until.mediumDate)"
        case (nil, nil): nil
        }
    }
}
