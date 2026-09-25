import SwiftUI

/// The six primary destinations surfaced as quick actions on the home screen.
enum Feature: String, Identifiable, CaseIterable {
    case visits, testResults, medication, healthSummary, letters, messages

    var id: String { rawValue }

    var title: String {
        switch self {
        case .visits: "Visits"
        case .testResults: "Test Results"
        case .medication: "Medication"
        case .healthSummary: "Health Summary"
        case .letters: "Letters"
        case .messages: "Messages"
        }
    }

    var systemImage: String {
        switch self {
        case .visits: "calendar"
        case .testResults: "testtube.2"
        case .medication: "pills.fill"
        case .healthSummary: "heart.text.square.fill"
        case .letters: "doc.text.fill"
        case .messages: "envelope.fill"
        }
    }

    var accent: Color {
        switch self {
        case .visits: Theme.teal
        case .testResults: Theme.green
        case .medication: Theme.orange
        case .healthSummary: Theme.red
        case .letters: Theme.yellow
        case .messages: Theme.brand
        }
    }
}

/// A unified "what's new" entry composed from results and messages.
private struct ActivityItem: Identifiable {
    let id: String
    let icon: String
    let tint: Color
    let title: String
    let subtitle: String
    let date: Date
    let isNew: Bool
}

struct DashboardView: View {
    let profile: PatientProfile
    @Environment(Session.self) private var session

    @State private var upcoming: [Appointment] = []
    @State private var activity: [ActivityItem] = []
    @State private var isLoading = true
    @State private var showPersona = false
    @State private var activeAccountID: String = ""

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    private var activeAccount: LinkedAccount? {
        profile.linkedAccounts.first { $0.id == activeAccountID } ?? profile.linkedAccounts.first
    }

    /// Colour tied to the active account, matching the persona switcher.
    private var activeTint: Color {
        guard let idx = profile.linkedAccounts.firstIndex(where: { $0.id == activeAccountID }) else {
            return Theme.brand
        }
        return Theme.leaves[idx % Theme.leaves.count]
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                header
                upcomingSection
                quickActions
                recentSection
            }
            .padding()
        }
        .background(.background.secondary)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showPersona = true } label: {
                    Text(activeAccount?.initials ?? profile.initials)
                        .font(.headline.weight(.bold))
                        .foregroundStyle(activeTint)
                }
                .accessibilityLabel("Switch account")
            }
        }
        .navigationDestination(for: Feature.self) { destination(for: $0) }
        .sheet(isPresented: $showPersona) {
            PersonaSwitcherSheet(accounts: profile.linkedAccounts, selectedID: $activeAccountID)
        }
        .task {
            if activeAccountID.isEmpty { activeAccountID = profile.linkedAccounts.first?.id ?? profile.id }
            await load()
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(greeting)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(activeAccount?.name ?? profile.preferredName)
                .font(.system(.largeTitle, design: .rounded).bold())
                .foregroundStyle(Theme.ink)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: .now)
        let part = switch hour {
        case 5..<12: "Good morning"
        case 12..<17: "Good afternoon"
        default: "Good evening"
        }
        return part + ","
    }

    // MARK: - Upcoming appointments

    @ViewBuilder
    private var upcomingSection: some View {
        sectionHeader("Upcoming", systemImage: "calendar", destination: .visits)

        if isLoading {
            AppointmentCardSkeleton()
        } else if upcoming.isEmpty {
            emptyCard("No upcoming appointments", systemImage: "calendar.badge.checkmark")
        } else {
            ForEach(upcoming) { appointment in
                UpcomingAppointmentCard(appointment: appointment)
            }
        }
    }

    // MARK: - Quick actions

    private var quickActions: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Quick actions")
                .font(.headline)
                .foregroundStyle(Theme.ink)
            LazyVGrid(columns: columns, spacing: 14) {
                ForEach(Feature.allCases) { feature in
                    NavigationLink(value: feature) {
                        QuickActionTile(feature: feature)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Recent activity

    @ViewBuilder
    private var recentSection: some View {
        Text("Recent")
            .font(.headline)
            .foregroundStyle(Theme.ink)

        if isLoading {
            VStack(spacing: 10) {
                ForEach(0..<3, id: \.self) { _ in
                    RecentRowSkeleton()
                }
            }
        } else if activity.isEmpty {
            emptyCard("Nothing new to show", systemImage: "sparkles")
        } else {
            VStack(spacing: 10) {
                ForEach(activity) { RecentRow(item: $0) }
            }
        }
    }

    // MARK: - Building blocks

    private func sectionHeader(_ title: String, systemImage: String, destination: Feature) -> some View {
        HStack {
            Text(title)
                .font(.headline)
                .foregroundStyle(Theme.ink)
            Spacer()
            NavigationLink(value: destination) {
                Text("See all")
                    .font(.subheadline.weight(.medium))
            }
        }
    }

    private func emptyCard(_ text: String, systemImage: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .foregroundStyle(Theme.brand)
            Text(text)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(.background, in: .rect(cornerRadius: 16))
    }

    @ViewBuilder
    private func destination(for feature: Feature) -> some View {
        switch feature {
        case .visits: AppointmentsView(patientID: profile.id)
        case .testResults: TestResultsView(patientID: profile.id)
        case .medication: MedicationsView(patientID: profile.id)
        case .healthSummary: HealthSummaryView(patientID: profile.id)
        case .letters:
            ContentUnavailableView("No letters", systemImage: "doc.text",
                                   description: Text("Letters from your care team will appear here."))
                .navigationTitle("Letters")
        case .messages: MessagesView(patientID: profile.id)
        }
    }

    // MARK: - Loading

    private func load() async {
        isLoading = true
        async let appointments = try? session.service.appointments(for: profile.id)
        async let results = try? session.service.testResults(for: profile.id)
        async let messages = try? session.service.messages(for: profile.id)

        let appts = await appointments ?? []
        let res = await results ?? []
        let msgs = await messages ?? []

        upcoming = appts
            .filter { $0.status == .scheduled }
            .sorted { $0.date < $1.date }

        var items: [ActivityItem] = []
        for m in msgs {
            items.append(ActivityItem(
                id: "msg-\(m.id)", icon: "envelope.fill", tint: Theme.brand,
                title: m.subject, subtitle: m.sender, date: m.date, isNew: m.isUnread))
        }
        for r in res.prefix(4) {
            items.append(ActivityItem(
                id: "res-\(r.id)", icon: "testtube.2", tint: Theme.green,
                title: r.name, subtitle: "Result available", date: r.date, isNew: r.isUnread))
        }
        activity = items.sorted { $0.date > $1.date }

        isLoading = false
    }
}

// MARK: - Subviews

private struct UpcomingAppointmentCard: View {
    let appointment: Appointment

    var body: some View {
        HStack(spacing: 16) {
            VStack(spacing: 2) {
                Text(appointment.date.formatted(.dateTime.day()))
                    .font(.title2.bold())
                Text(appointment.date.formatted(.dateTime.month(.abbreviated)))
                    .font(.caption).textCase(.uppercase)
            }
            .foregroundStyle(.white)
            .frame(width: 56, height: 56)
            .background(Theme.brand, in: .rect(cornerRadius: 14))

            VStack(alignment: .leading, spacing: 3) {
                Text(appointment.title).font(.headline)
                Text(appointment.department)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Label(appointment.date.formatted(date: .omitted, time: .shortened),
                      systemImage: appointment.isTelehealth ? "phone.fill" : "mappin.and.ellipse")
                    .font(.caption)
                    .foregroundStyle(Theme.brand)
            }
            Spacer()
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 20))
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(Theme.brand.opacity(0.2), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.05), radius: 8, y: 3)
    }
}

private struct QuickActionTile: View {
    let feature: Feature

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: feature.systemImage)
                .font(.title2)
                .foregroundStyle(feature.accent)
                .frame(width: 56, height: 56)
                .background(feature.accent.opacity(0.14), in: .circle)
            Text(feature.title)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Theme.ink)
                .multilineTextAlignment(.center)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 128)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 20))
    }
}

private struct AppointmentCardSkeleton: View {
    var body: some View {
        HStack(spacing: 16) {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.gray.opacity(0.25))
                .frame(width: 56, height: 56)
            VStack(alignment: .leading, spacing: 8) {
                SkeletonBar(width: 160, height: 14)
                SkeletonBar(width: 210, height: 11)
                SkeletonBar(width: 90, height: 11)
            }
            Spacer()
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 20))
        .shimmering()
    }
}

private struct RecentRowSkeleton: View {
    var body: some View {
        HStack(spacing: 14) {
            Circle()
                .fill(Color.gray.opacity(0.25))
                .frame(width: 40, height: 40)
            VStack(alignment: .leading, spacing: 8) {
                SkeletonBar(width: 180, height: 12)
                SkeletonBar(width: 110, height: 10)
            }
            Spacer()
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 16))
        .shimmering()
    }
}

private struct RecentRow: View {
    let item: ActivityItem

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: item.icon)
                .foregroundStyle(item.tint)
                .frame(width: 40, height: 40)
                .background(item.tint.opacity(0.14), in: .circle)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(item.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text(item.date.mediumDate)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                if item.isNew {
                    Text("NEW")
                        .font(.caption2.bold())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Theme.red, in: .capsule)
                }
            }
        }
        .padding(12)
        .background(.background, in: .rect(cornerRadius: 16))
    }
}

#Preview {
    NavigationStack {
        DashboardView(profile: PatientProfile(
            id: "p", fullName: "Sallie Anderson", preferredName: "Sallie", initials: "S",
            linkedAccounts: [
                LinkedAccount(id: "acct-sallie", name: "Sallie", initials: "S", unreadCount: 1),
                LinkedAccount(id: "acct-sal", name: "Sal", initials: "S", unreadCount: 0)
            ]))
    }
    .environment(Session())
}
