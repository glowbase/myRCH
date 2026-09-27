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

    /// Browse's icon and its colour, one bright colour per section like the
    /// Health app's categories. Separate from `systemImage`/`accent`, which
    /// the section screens use.
    var tileArt: (symbol: String, color: Color) {
        switch self {
        case .visits: ("calendar.badge.clock", .red)
        case .testResults: ("cross.vial.fill", .indigo)
        case .medication: ("pills.fill", .cyan)
        case .immunisations: ("bandage.fill", .purple)
        case .allergies: ("allergens.fill", .orange)
        case .growthCharts: ("figure.and.child.holdinghands", .green)
        case .trackHealth: ("figure.walk.motion", .teal)
        case .implants: ("cross.case.fill", .brown)
        case .letters: ("envelope.open.fill", .yellow)
        case .healthSummary: ("heart.text.clipboard.fill", .pink)
        case .messages: ("bubble.left.and.bubble.right.fill", .blue)
        case .sharing: ("person.2.fill", .mint)
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
    /// From the record's print header; the account switcher has first names
    /// only. Shown on the UR sheet, where staff need the full name.
    @State private var fullName: String?
    /// The first name, a little larger than a large title (34pt).
    @ScaledMetric(relativeTo: .largeTitle) private var nameSize: CGFloat = 40

    @State private var explore: ExploreMoreFeed?
    /// Explore More cards closed with ✕, remembered across launches.
    @AppStorage("dismissedExploreItems") private var dismissedExplore = ""

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
                exploreMoreSection
            }
            .padding()
        }
        // Grouped background, like the app's other screens: grey under white
        // cards in light mode, black under dark-grey cards in dark mode.
        // (`.background.secondary` matched the cards' grey in dark mode.)
        .background(Color(.systemGroupedBackground))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink {
                    NotificationsView(patientID: session.patientID)
                } label: {
                    Image(systemName: unreadCount > 0 ? "bell.badge" : "bell")
                        .symbolRenderingMode(.multicolor)
                }
                .accessibilityLabel(unreadCount > 0 ? "Notifications, \(unreadCount) unread" : "Notifications")
            }
            // Like the Health app's profile picture: opens settings and accounts.
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink {
                    SettingsView(profile: profile)
                } label: {
                    AvatarView(initials: session.activeAccount?.initials ?? profile.initials,
                               tint: session.activeTint, size: 32)
                }
                .accessibilityLabel("Profile and settings")
            }
        }
        .navigationDestination(for: Feature.self) { FeatureDestination(feature: $0) }
        .sheet(isPresented: $showsAddGoal) {
            AddGoalSheet { goals.append($0) }
        }
        .sheet(isPresented: $showsMRN) {
            if let mrn {
                MRNSheet(mrn: mrn, name: displayName)
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
                    .font(.system(size: nameSize, weight: .bold, design: .rounded))
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

    /// Full name for the UR sheet.
    private var displayName: String {
        fullName ?? session.activeAccount?.name ?? profile.fullName
    }

    /// e.g. "8 years · UR 12345678". Tapping the UR number shows it full size.
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
                            Text("UR \(mrn)").fontWeight(.medium)
                            Image(systemName: "arrow.up.left.and.arrow.down.right")
                                .font(.caption2.weight(.semibold))
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("UR number, \(MRNSheet.spokenDigits(mrn))")
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
            SummarySectionHeader(title: "Upcoming Visits", destination: Feature.visits)
            if isLoading {
                AppointmentCardSkeleton()
            } else if upcoming.isEmpty {
                emptyCard("No upcoming appointments", systemImage: "calendar.badge.checkmark")
            } else {
                ForEach(upcoming.prefix(3)) { appointment in
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
            SummarySectionHeader(title: "Recent Results", destination: Feature.testResults)
            if isLoading {
                listSkeleton(rows: 3)
            } else if results.isEmpty {
                emptyCard("No test results yet", systemImage: "testtube.2")
            } else {
                ForEach(results.prefix(3)) { result in
                    NavigationLink {
                        TestResultDetailView(result: result)
                    } label: {
                        ResultSummaryCard(result: result)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Medication

    private var medicationSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SummarySectionHeader(title: "Medication", destination: Feature.medication)
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
            SummarySectionHeader(title: "Immunisations", destination: Feature.immunisations)
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
                                .foregroundStyle(Feature.immunisations.tileArt.color)
                                .frame(width: 40, height: 40)
                                .background(Feature.immunisations.tileArt.color.opacity(0.14), in: .circle)
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
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: Theme.cardRadius))
    }

    // MARK: - Explore more

    private var visibleExplore: [ExploreItem] {
        let dismissed = Set(dismissedExplore.split(separator: "\n").map(String.init))
        return (explore?.items ?? []).filter { !dismissed.contains($0.id) }
    }

    private var hiddenExploreCount: Int {
        (explore?.items.count ?? 0) - visibleExplore.count
    }

    @ViewBuilder
    private var exploreMoreSection: some View {
        if let explore, !visibleExplore.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                SummarySectionHeader<Feature>(title: explore.title)
                ForEach(visibleExplore) { item in
                    ExploreCard(item: item) {
                        withAnimation {
                            dismissedExplore += (dismissedExplore.isEmpty ? "" : "\n") + item.id
                        }
                    }
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
                }
                if hiddenExploreCount > 0 {
                    showHiddenExploreButton
                }
            }
        } else if explore != nil, hiddenExploreCount > 0 {
            // Every card closed: keep a way back rather than nothing.
            showHiddenExploreButton
        }
    }

    private var showHiddenExploreButton: some View {
        Button {
            withAnimation { dismissedExplore = "" }
        } label: {
            Label(hiddenExploreCount == 1 ? "Show 1 hidden card" : "Show \(hiddenExploreCount) hidden cards",
                  systemImage: "arrow.uturn.backward")
                .font(.subheadline.weight(.medium))
        }
        .frame(maxWidth: .infinity)
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
            .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: Theme.cardRadius))
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
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: Theme.cardRadius))
    }

    private func listSkeleton(rows: Int) -> some View {
        VStack(spacing: 0) {
            ForEach(0..<rows, id: \.self) { index in
                ListRowSkeleton()
                if index < rows - 1 { Divider().padding(.leading, 68) }
            }
        }
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: Theme.cardRadius))
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
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: Theme.cardRadius))
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
        async let exploreTask = try? service.exploreMore(for: id)
        async let headerTask = try? service.recordHeader(for: id)

        let appointments = await appointmentsTask ?? []
        let messages = await messagesTask ?? []
        results = (await resultsTask ?? []).sorted(by: TestResult.newestFirst)
        medications = (await medicationsTask ?? []).filter(\.isActive)
        issues = await issuesTask ?? []
        let header = await headerTask
        mrn = header?.urNumber
        fullName = header?.fullName
        allergies = await allergiesTask ?? []
        immunisations = ImmunisationGroup.group(await immunisationsTask ?? [])
        explore = await exploreTask

        upcoming = appointments
            .filter { $0.status == .scheduled }
            .sorted { $0.date < $1.date }
        unreadCount = messages.filter(\.isUnread).count + results.filter(\.isUnread).count

        isLoading = false
    }
}

// MARK: - Subviews

/// The UR number in large monospaced digits, for reading out or showing to
/// staff. Like a Wallet pass, it turns the screen up to full brightness while
/// open, and puts it back on closing or leaving the app.
private struct MRNSheet: View {
    let mrn: String
    let name: String
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var copied = false
    /// The brightness before the sheet opened, to restore.
    @State private var savedBrightness: CGFloat?

    private var screen: UIScreen? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }?.screen
    }

    private func brighten() {
        guard savedBrightness == nil, let screen else { return }
        savedBrightness = screen.brightness
        screen.brightness = 1
    }

    private func restoreBrightness() {
        guard let saved = savedBrightness else { return }
        screen?.brightness = saved
        savedBrightness = nil
    }

    /// "12345678" → "1 2 3 4 5 6 7 8", so VoiceOver reads digits, not a number.
    static func spokenDigits(_ mrn: String) -> String {
        mrn.map(String.init).joined(separator: " ")
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                VStack(spacing: 6) {
                    Text("UR Number")
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
        .presentationDetents([.height(330)])
        .onAppear { brighten() }
        .onDisappear { restoreBrightness() }
        // Leaving the app restores it (as Wallet does); coming back re-brightens.
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { brighten() } else { restoreBrightness() }
        }
    }
}

/// The next visit, Health-style: "Visit" in the Visits colour with the day
/// at the top, then what it is, where, and when.
private struct UpcomingAppointmentCard: View {
    let appointment: Appointment

    private var dayText: String {
        let calendar = Calendar.current
        if calendar.isDateInToday(appointment.date) { return "Today" }
        if calendar.isDateInTomorrow(appointment.date) { return "Tomorrow" }
        return appointment.date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
    }

    var body: some View {
        let art = Feature.visits.tileArt
        SummaryCard(category: appointment.isTelehealth ? "Telehealth" : "Visit",
                    systemImage: appointment.isTelehealth ? "video.fill" : art.symbol,
                    color: art.color, detail: dayText) {
            VStack(alignment: .leading, spacing: 4) {
                Text(appointment.date.formatted(date: .omitted, time: .shortened))
                    .font(.system(.title, design: .rounded).bold())
                    .foregroundStyle(.primary)
                Text(appointment.title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                Text(appointment.department)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// A recent result, Health-style: the test type in the Results colour with
/// the date, then the test name and whether it's in range. Fetches details
/// for the range status, like the list row does (cached by the service).
private struct ResultSummaryCard: View {
    @Environment(Session.self) private var session
    let result: TestResult
    @State private var detailed: TestResult?

    var body: some View {
        let art = Feature.testResults.tileArt
        SummaryCard(category: "Test Result", systemImage: result.systemImage,
                    color: art.color, detail: result.date.shortRelativeDate) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text(result.name)
                        .font(.system(.title3, design: .rounded).bold())
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)
                    if result.isUnread {
                        Circle().fill(Theme.brand).frame(width: 8, height: 8)
                            .accessibilityLabel("Unread")
                    }
                }
                if let status = (detailed ?? result).rangeStatus {
                    RangeStatusPill(status: status)
                }
            }
        }
        .animation(.default, value: detailed?.rangeStatus)
        .task(id: result.id) {
            detailed = try? await session.service.testResultDetails(result, for: session.patientID)
        }
    }
}

/// A Health-style suggestion card: picture on the left, then title, text
/// and a capsule button, with ✕ to close it.
private struct ExploreCard: View {
    let item: ExploreItem
    let onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            icon
                .frame(width: 44, height: 44)
                .padding(.top, 4)
            VStack(alignment: .leading, spacing: 8) {
                Text(item.title)
                    .font(.headline)
                    .padding(.trailing, 28)
                Text(item.body)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    if let primary = item.primary {
                        Link(primary.title, destination: primary.url)
                            .buttonStyle(.borderedProminent)
                            .buttonBorderShape(.capsule)
                    }
                    if let secondary = item.secondary {
                        Link(secondary.title, destination: secondary.url)
                            .buttonStyle(.bordered)
                            .buttonBorderShape(.capsule)
                    }
                }
                .font(.subheadline.weight(.semibold))
                .tint(Theme.brand)
                .padding(.top, 4)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(18)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: Theme.cardRadius))
        .overlay(alignment: .topTrailing) {
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 28)
                    .background(Color(.tertiarySystemFill), in: .circle)
            }
            .buttonStyle(.plain)
            .padding(12)
            .accessibilityLabel("Dismiss \(item.title)")
        }
    }

    /// A symbol chosen for what the card is about, two-tone like the Health
    /// app's suggestion art: each layer of the symbol in its own colour.
    /// (Matched on the title and link, since the portal's `IconKey` is a
    /// generic keyword or a small logo.)
    private var icon: some View {
        let art = Self.artwork(for: item)
        return Image(systemName: art.symbol)
            .symbolRenderingMode(.palette)
            .foregroundStyle(art.primary, art.secondary)
            .font(.system(size: 34, weight: .medium))
            .accessibilityHidden(true)
    }

    private static func artwork(for item: ExploreItem) -> (symbol: String, primary: Color, secondary: Color) {
        let text = (item.title + " " + (item.primary?.url.absoluteString ?? "")).lowercased()
        if text.contains("support") || text.contains("foundation") || text.contains("donat") {
            return ("hands.and.sparkles.fill", .pink, .pink.lighter)
        }
        if text.contains("kidsinfo") || text.contains("health info") || text.contains("fact sheet") {
            return ("heart.text.clipboard.fill", .blue, .cyan)
        }
        if text.contains("telehealth") || text.contains("video call") {
            return ("video.fill.badge.checkmark", .teal, .mint)
        }
        if text.contains("speak up") || text.contains("oneteam") || text.contains("vimeo") {
            return ("person.2.wave.2.fill", .indigo, .indigo.lighter)
        }
        if text.contains("survey") || text.contains("feedback") {
            return ("star.bubble.fill", .orange, .orange.lighter)
        }
        return ("lightbulb.max.fill", .yellow, .yellow.lighter)
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
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: Theme.cardRadius))
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
