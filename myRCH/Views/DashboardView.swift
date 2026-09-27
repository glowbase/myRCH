import SwiftUI

/// Sections of the app, reachable from Browse and the dashboard.
enum Feature: String, Identifiable, CaseIterable {
    case visits, testResults, medication, immunisations, allergies
    case growthCharts, trackHealth, implants, letters
    case healthSummary, messages, sharing

    var id: String { rawValue }

    /// Browse's tiles, alphabetical like the Health app's categories.
    static var browsable: [Feature] {
        allCases.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    var title: String {
        switch self {
        case .visits: "Visits"
        case .testResults: "Test Results"
        case .medication: "Medication"
        case .immunisations: "Immunisations"
        case .allergies: "Allergies"
        case .growthCharts: "Growth Charts"
        case .trackHealth: "Track My Health"
        case .implants: "Implants"
        case .letters: "Letters"
        case .healthSummary: "Health Summary"
        case .messages: "Messages"
        case .sharing: "Share My Record"
        }
    }

    var systemImage: String {
        switch self {
        case .visits: "calendar"
        case .testResults: "testtube.2"
        case .medication: "pills.fill"
        case .immunisations: "syringe.fill"
        case .allergies: "allergens"
        case .growthCharts: "chart.line.uptrend.xyaxis"
        case .trackHealth: "waveform.path.ecg"
        case .implants: "cross.case.fill"
        case .letters: "doc.text.fill"
        case .healthSummary: "heart.text.square.fill"
        case .messages: "envelope.fill"
        case .sharing: "folder.badge.person.crop"
        }
    }

    var accent: Color {
        switch self {
        case .visits, .growthCharts: Theme.teal
        // Not green: green means "within normal range" on results.
        case .testResults: Theme.blue
        case .trackHealth: Theme.green
        case .medication: Theme.orange
        case .immunisations: Theme.proxy
        case .allergies, .healthSummary: Theme.red
        case .implants: Theme.yellow
        // Navy, not yellow: yellow icons are too faint on white for a screen
        // of letter rows.
        case .letters: Theme.ink
        case .messages, .sharing: Theme.brand
        }
    }
}

struct DashboardView: View {
    let profile: PatientProfile
    @Environment(Session.self) private var session
    @Environment(\.scenePhase) private var scenePhase

    @State private var isLoading = true
    @State private var upcoming: [Appointment] = []
    @State private var results: [TestResult] = []
    @State private var medications: [Medication] = []
    @State private var issues: [HealthIssue] = []
    @State private var allergies: [Allergy] = []
    @State private var immunisations: [ImmunisationGroup] = []
    @State private var unreadCount = 0
    @State private var mrn: String?
    @State private var showsMRN = false

    @State private var goals: [String] = []
    @State private var showsAddGoal = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                header
                upcomingSection
                resultsSection
                medicationSection
                immunisationSection
                goalsCard
                sharingCard
            }
            .padding()
        }
        // Grouped background, like the app's other screens: grey under white
        // cards in light mode, black under dark-grey cards in dark mode.
        // (`.background.secondary` matched the cards' grey in dark mode.)
        .background(Color(.systemGroupedBackground))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                NavigationLink {
                    SettingsView(profile: profile)
                } label: {
                    Image(systemName: "gearshape")
                }
                .accessibilityLabel("Settings")
            }
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink {
                    NotificationsView(patientID: session.patientID)
                } label: {
                    Image(systemName: unreadCount > 0 ? "bell.badge" : "bell")
                        .symbolRenderingMode(.multicolor)
                }
                .accessibilityLabel(unreadCount > 0 ? "Notifications, \(unreadCount) unread" : "Notifications")
            }
        }
        .navigationDestination(for: Feature.self) { FeatureDestination(feature: $0) }
        .sheet(isPresented: $showsAddGoal) {
            AddGoalSheet { goals.append($0) }
        }
        .sheet(isPresented: $showsMRN) {
            if let mrn {
                MRNSheet(mrn: mrn, name: session.activeAccount?.name ?? profile.fullName)
            }
        }
        .task(id: session.patientID) { await load() }
        // The pull-to-refresh spinner is the progress indicator, so keep the
        // current cards on screen instead of swapping in skeletons.
        .refreshable {
            await session.refreshData()
            await load(showsPlaceholders: false)
        }
        // Back from the background: reload quietly. The cache answers if the
        // data is under five minutes old; otherwise this fetches fresh data.
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await load(showsPlaceholders: false) } }
        }
    }

    // MARK: - Header (greeting, key facts, diagnosis + allergy pills)

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(greeting)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(session.activeAccount?.name ?? profile.preferredName)
                    .font(.system(.largeTitle, design: .rounded).bold())
                    .foregroundStyle(Theme.ink)
                factsLine
            }

            if isLoading {
                HStack(spacing: 8) {
                    ForEach(["Placeholder", "Placeholder issue", "Allergy"], id: \.self) { text in
                        Pill(text: text, systemImage: "heart.text.square.fill", tint: Theme.brand)
                    }
                }
                .redacted(reason: .placeholder)
            } else {
                NavigationLink(value: Feature.healthSummary) {
                    FlowLayout(spacing: 8) {
                        ForEach(issues) { issue in
                            // Neutral, so the allergy pills are the ones that stand out.
                            Pill(text: issue.name, systemImage: "heart.text.square.fill", tint: .primary)
                        }
                        if allergies.isEmpty {
                            Pill(text: "No known allergies", systemImage: "checkmark", tint: Theme.green)
                        } else {
                            ForEach(allergies) { allergy in
                                Pill(text: allergy.substance, systemImage: "allergens", tint: Theme.red)
                            }
                        }
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(pillsAccessibilityLabel)
                .accessibilityHint("Opens the health summary")
            }
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

    /// e.g. "8 years · MRN 12345678". Tapping the MRN shows it full size.
    @ViewBuilder
    private var factsLine: some View {
        let age = session.activeAccount?.dateOfBirth?.ageDescription
        if age != nil || mrn != nil {
            HStack(spacing: 5) {
                if let age { Text(age) }
                if age != nil, mrn != nil { Text("·") }
                if let mrn {
                    Button { showsMRN = true } label: {
                        HStack(spacing: 4) {
                            Text("MRN \(mrn)").fontWeight(.medium)
                            Image(systemName: "arrow.up.left.and.arrow.down.right")
                                .font(.caption2.weight(.semibold))
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Medical record number, \(MRNSheet.spokenDigits(mrn))")
                    .accessibilityHint("Shows it in large print")
                }
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
    }

    private var pillsAccessibilityLabel: String {
        let issueText = issues.isEmpty ? "No health issues" : "Health issues: " + issues.map(\.name).formatted(.list(type: .and))
        let allergyText = allergies.isEmpty ? "No known allergies" : "Allergies: " + allergies.map(\.substance).formatted(.list(type: .and))
        return "\(issueText). \(allergyText)."
    }

    // MARK: - Upcoming appointments

    private var upcomingSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Upcoming", destination: .visits)
            if isLoading {
                AppointmentCardSkeleton()
            } else if upcoming.isEmpty {
                emptyCard("No upcoming appointments", systemImage: "calendar.badge.checkmark")
            } else {
                ForEach(upcoming) { appointment in
                    NavigationLink {
                        AppointmentDetailView(appointment: appointment)
                    } label: {
                        UpcomingAppointmentCard(appointment: appointment)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Test results

    private var resultsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Recent Results", destination: .testResults)
            if isLoading {
                listSkeleton(rows: 3)
            } else if results.isEmpty {
                emptyCard("No test results yet", systemImage: "testtube.2")
            } else {
                cardList(results.prefix(4)) { result in
                    NavigationLink {
                        TestResultDetailView(result: result)
                    } label: {
                        HStack {
                            TestResultRow(result: result)
                            Image(systemName: "chevron.right")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Medication

    private var medicationSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Medication", destination: .medication)
            if isLoading {
                listSkeleton(rows: 2)
            } else if medications.isEmpty {
                emptyCard("No current medication", systemImage: "pills")
            } else {
                cardList(medications.prefix(3)) { medication in
                    NavigationLink {
                        MedicationDetailView(medication: medication)
                    } label: {
                        HStack {
                            MedicationRow(medication: medication)
                            Image(systemName: "chevron.right")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Immunisations

    private var immunisationSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Immunisations", destination: .immunisations)
            if isLoading {
                listSkeleton(rows: 2)
            } else if immunisations.isEmpty {
                emptyCard("No immunisations on file", systemImage: "syringe")
            } else {
                cardList(immunisations.prefix(3)) { group in
                    NavigationLink {
                        ImmunisationDetailView(group: group, patientID: session.patientID)
                    } label: {
                        HStack(spacing: 14) {
                            Image(systemName: "syringe.fill")
                                .foregroundStyle(Theme.proxy)
                                .frame(width: 40, height: 40)
                                .background(Theme.proxy.opacity(0.14), in: .circle)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(group.name)
                                    .font(.subheadline.weight(.semibold))
                                Text(datesOnFile(group.dates))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func datesOnFile(_ dates: [Date]) -> String {
        guard let latest = dates.first else { return "" }
        return dates.count > 1 ? "\(latest.mediumDate), +\(dates.count - 1) more" : latest.mediumDate
    }

    // MARK: - Health goals

    private var goalsCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 14) {
                Image(systemName: "target")
                    .foregroundStyle(Theme.green)
                    .frame(width: 40, height: 40)
                    .background(Theme.green.opacity(0.14), in: .circle)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Health goals")
                        .font(.subheadline.weight(.semibold))
                    Text(goals.isEmpty ? "Share a goal with your care team" : "\(goals.count) shared with your care team")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Add", systemImage: "plus") { showsAddGoal = true }
                    .labelStyle(.titleAndIcon)
                    .font(.subheadline.weight(.semibold))
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.capsule)
                    .tint(Theme.brand)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)

            ForEach(goals, id: \.self) { goal in
                Divider().padding(.leading, 68)
                Label(goal, systemImage: "checkmark.circle")
                    .font(.subheadline)
                    .foregroundStyle(Theme.ink)
                    .padding(.leading, 68)
                    .padding(.trailing, 14)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 20))
    }

    // MARK: - Share my record

    private var sharingCard: some View {
        NavigationLink(value: Feature.sharing) {
            HStack(spacing: 14) {
                Image(systemName: Feature.sharing.systemImage)
                    .foregroundStyle(Theme.yellow)
                    .frame(width: 40, height: 40)
                    .background(Theme.yellow.opacity(0.18), in: .circle)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Share my record")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text("With family, carers and other providers")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 20))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Building blocks

    /// A single white rounded container of rows separated by inset dividers.
    private func cardList<Items: RandomAccessCollection, Row: View>(
        _ items: Items, @ViewBuilder row: @escaping (Items.Element) -> Row
    ) -> some View where Items.Element: Identifiable {
        VStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                row(item)
                if index < items.count - 1 {
                    Divider().padding(.leading, 68)
                }
            }
        }
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 20))
    }

    private func listSkeleton(rows: Int) -> some View {
        VStack(spacing: 0) {
            ForEach(0..<rows, id: \.self) { index in
                ListRowSkeleton()
                if index < rows - 1 { Divider().padding(.leading, 68) }
            }
        }
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 20))
    }

    private func sectionHeader(_ title: String, destination: Feature) -> some View {
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
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 20))
    }

    // MARK: - Loading

    private func load(showsPlaceholders: Bool = true) async {
        if showsPlaceholders { isLoading = true }
        let service = session.service
        let id = session.patientID
        async let appointmentsTask = try? service.appointments(for: id)
        async let resultsTask = try? service.testResults(for: id)
        async let messagesTask = try? service.messages(for: id)
        async let medicationsTask = try? service.medications(for: id)
        async let issuesTask = try? service.healthIssues(for: id)
        async let allergiesTask = try? service.allergies(for: id)
        async let immunisationsTask = try? service.immunisations(for: id)
        async let mrnTask = try? service.medicalRecordNumber(for: id)

        let appointments = await appointmentsTask ?? []
        let messages = await messagesTask ?? []
        results = (await resultsTask ?? []).sorted(by: TestResult.newestFirst)
        medications = (await medicationsTask ?? []).filter(\.isActive)
        issues = await issuesTask ?? []
        mrn = await mrnTask ?? nil
        allergies = await allergiesTask ?? []
        immunisations = ImmunisationGroup.group(await immunisationsTask ?? [])

        upcoming = appointments
            .filter { $0.status == .scheduled }
            .sorted { $0.date < $1.date }
        unreadCount = messages.filter(\.isUnread).count + results.filter(\.isUnread).count

        isLoading = false
    }
}

// MARK: - Subviews

/// The MRN in large monospaced digits, for reading out or showing to staff.
private struct MRNSheet: View {
    let mrn: String
    let name: String
    @Environment(\.dismiss) private var dismiss
    @State private var copied = false

    /// "12345678" → "1 2 3 4 5 6 7 8", so VoiceOver reads digits, not a number.
    static func spokenDigits(_ mrn: String) -> String {
        mrn.map(String.init).joined(separator: " ")
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                VStack(spacing: 6) {
                    Text("Medical Record Number")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(name)
                        .font(.headline)
                }
                Text(mrn)
                    .font(.system(size: 60, weight: .bold, design: .monospaced))
                    .lineLimit(1)
                    .minimumScaleFactor(0.4)
                    .textSelection(.enabled)
                    .accessibilityLabel(Self.spokenDigits(mrn))
                Button {
                    UIPasteboard.general.string = mrn
                    copied = true
                } label: {
                    Label(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc")
                        .contentTransition(.symbolEffect(.replace))
                }
                .buttonStyle(.bordered)
                .sensoryFeedback(.success, trigger: copied) { _, now in now }
            }
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
    }
}

private struct UpcomingAppointmentCard: View {
    let appointment: Appointment

    var body: some View {
        HStack(spacing: 16) {
            VStack(spacing: 2) {
                Text(appointment.date.formatted(.dateTime.day()))
                    .font(.title2.bold())
                    .foregroundStyle(Feature.visits.accent)
                // Small text in the adaptive secondary colour; teal would be
                // too faint on the tint at caption size.
                Text(appointment.date.formatted(.dateTime.month(.abbreviated)))
                    .font(.caption).textCase(.uppercase)
                    .foregroundStyle(.secondary)
            }
            // Same soft tint as the Visits quick-link tile.
            .frame(width: 56, height: 56)
            .background(Feature.visits.accent.opacity(0.14), in: .rect(cornerRadius: 14))

            VStack(alignment: .leading, spacing: 3) {
                Text(appointment.title).font(.headline)
                Text(appointment.department)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Label(appointment.date.formatted(date: .omitted, time: .shortened),
                      systemImage: appointment.isTelehealth ? "phone.fill" : "mappin.and.ellipse")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 20))
    }
}

private struct AppointmentCardSkeleton: View {
    var body: some View {
        HStack(spacing: 16) {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.gray.opacity(0.25))
                .frame(width: 56, height: 56)
            VStack(alignment: .leading, spacing: 3) {
                Text("Placeholder appointment").font(.headline)
                Text("Placeholder department name").font(.subheadline)
                Text("00:00 am").font(.caption)
            }
            Spacer()
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 20))
        .redacted(reason: .placeholder)
    }
}

/// Skeleton row shown inside a card list while loading.
private struct ListRowSkeleton: View {
    var body: some View {
        HStack(spacing: 14) {
            Circle()
                .fill(Color.gray.opacity(0.25))
                .frame(width: 40, height: 40)
            VStack(alignment: .leading, spacing: 4) {
                Text("Placeholder row title").font(.subheadline.weight(.semibold))
                Text("Placeholder detail").font(.caption)
            }
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .redacted(reason: .placeholder)
    }
}

/// Small sheet for sharing a new health goal with the care team.
private struct AddGoalSheet: View {
    let onAdd: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("e.g. Sleep through the night", text: $text, axis: .vertical)
                        .lineLimit(2...4)
                        .focused($focused)
                } footer: {
                    Text("Your care team can discuss this goal with you at future visits.")
                }
            }
            .navigationTitle("New health goal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        onAdd(text.trimmingCharacters(in: .whitespacesAndNewlines))
                        dismiss()
                    }
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onAppear { focused = true }
        }
        .presentationDetents([.medium])
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
