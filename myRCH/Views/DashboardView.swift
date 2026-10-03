import SwiftUI

/// Sections of the app, reachable from Browse and the dashboard.
enum Feature: String, Identifiable, CaseIterable {
    case visits, testResults, medication, immunisations, allergies
    case growthCharts, trackHealth, implants, letters
    case healthSummary, messages, sharing, medicalID

    var id: String { rawValue }

    /// Browse's tiles, the everyday sections first (visits, results,
    /// medication, messages), then the rest roughly by how often they're
    /// needed, with the not-yet-available ones last.
    static let browsable: [Feature] = [
        .visits, .testResults, .medication, .messages,
        .letters, .medicalID, .immunisations, .allergies,
        .growthCharts, .healthSummary, .sharing,
        .trackHealth, .implants
    ]

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
        case .medicalID: "Medical ID"
        }
    }

    /// The section's one icon, matching what its screen shows (a syringe for
    /// immunisations, a chart for growth charts), used on Browse tiles, cards,
    /// search results and the section's own screens alike.
    var systemImage: String {
        switch self {
        case .visits: "calendar.badge.clock"
        case .testResults: "testtube.2"
        case .medication: "pills.fill"
        case .immunisations: "syringe.fill"
        case .allergies: "allergens.fill"
        case .growthCharts: "chart.line.uptrend.xyaxis"
        case .trackHealth: "waveform.path.ecg"
        case .implants: "cross.case.fill"
        case .letters: "envelope.open.fill"
        case .healthSummary: "heart.text.clipboard.fill"
        case .messages: "bubble.left.and.bubble.right.fill"
        case .sharing: "person.2.wave.2.fill"
        case .medicalID: "staroflife.fill"
        }
    }

    /// Browse's icon and its colour, one colour per section like the Health
    /// app's categories (`Theme.Section`). The icon is always `systemImage`,
    /// so a tile never shows something different from its screen.
    var tileArt: (symbol: String, color: Color) {
        let color: Color = switch self {
        case .visits: Theme.Section.visits
        case .testResults: Theme.Section.testResults
        case .medication: Theme.Section.medication
        case .immunisations: Theme.Section.immunisations
        case .allergies: Theme.Section.allergies
        case .growthCharts: Theme.Section.growthCharts
        case .trackHealth: Theme.Section.trackHealth
        case .implants: Theme.Section.implants
        case .letters: Theme.Section.letters
        case .healthSummary: Theme.Section.healthSummary
        case .messages: Theme.Section.messages
        case .sharing: Theme.Section.sharing
        case .medicalID: Theme.Section.medicalID
        }
        return (systemImage, color)
    }

    var accent: Color {
        switch self {
        case .visits, .growthCharts: Theme.teal
        // Not green: green means "within normal range" on results.
        case .testResults: Theme.blue
        case .trackHealth: Theme.green
        case .medication: Theme.medication
        case .immunisations: .purple
        case .allergies, .healthSummary: Theme.red
        case .implants: Theme.yellow
        // Navy, not yellow: yellow icons are too faint on white for a screen
        // of letter rows.
        case .letters: Theme.ink
        case .messages, .sharing: Theme.brand
        case .medicalID: Theme.red
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
    @State private var unreadMessages = 0
    @Environment(MedicationStore.self) private var medicationStore
    @State private var mrn: String?
    @State private var showsMRN = false
    /// From the record's print header; the account switcher has first names
    /// only. Shown on the UR sheet, where staff need the full name.
    @State private var fullName: String?
    @State private var explore: ExploreMoreFeed?
    /// Explore More cards closed with ✕, remembered across launches.
    @AppStorage("dismissedExploreItems") private var dismissedExplore = ""


    /// Pinned sections, in order (see `HomeLayout`).
    @AppStorage(HomeLayout.storageKey) private var homeSections = ""

    /// Home's search: everything from test results to fact sheets.
    @State private var searchText = ""
    /// The child's records to search, loaded when a search starts (cached
    /// by the service).
    @State private var searchIndex: SearchIndex?

    var body: some View {
        chrome(
            Group {
                if searchText.isEmpty {
                    dashboard
                } else {
                    SearchResultsList(query: searchText,
                                      features: Feature.browsable.filter { $0.title.localizedCaseInsensitiveContains(searchText) },
                                      index: searchIndex)
                }
            }
            // Under the large title, staying in the bar once it collapses.
            .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always),
                        prompt: "Search records and health info")
            .task(id: searchText.isEmpty) {
                guard !searchText.isEmpty, searchIndex == nil else { return }
                searchIndex = await SearchIndex.load(service: session.service, patientID: session.patientID)
            }
            .onChange(of: session.patientID) { searchIndex = nil }
        )
    }

    private var dashboard: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                // No spacing, so an absent digest leaves no gap; the card
                // pads itself when shown.
                VStack(alignment: .leading, spacing: 0) {
                    header
                    if !isLoading {
                        HomeDigestCard(results: results, upcoming: upcoming, unreadMessages: unreadMessages)
                    }
                }
                // Rearranged from Settings › Edit Home.
                ForEach(HomeLayout(stored: homeSections).pinned) { section in
                    self.section(section)
                }
                // Always last, like Articles in the Health app.
                HomeArticlesSection()
            }
            .padding(.horizontal)
            .padding(.bottom)
            // Less than the usual 16 above the chips, so they sit close
            // under the search bar.
            .padding(.top, 4)
        }
        // Grouped background, like the app's other screens: grey under white
        // cards in light mode, black under dark-grey cards in dark mode.
        // (`.background.secondary` matched the cards' grey in dark mode.)
        .background(Color(.systemGroupedBackground))
        // The pull-to-refresh spinner is the progress indicator, so keep the
        // current cards on screen instead of swapping in skeletons.
        .refreshable {
            await session.refreshData()
            await load(showsPlaceholders: false)
        }
    }

    /// Toolbar, links and loading, kept while searching too.
    private func chrome(_ content: some View) -> some View {
        content
        // The child's name as a large title, shrinking into the bar on scroll.
        .navigationTitle(session.activeAccount?.name ?? profile.preferredName)
        // Under the small title once collapsed (the large title uses the
        // tappable `factsLine` below instead).
        .navigationSubtitle(factsText)
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            // Age and UR number under the large title; the UR stays tappable.
            ToolbarItem(placement: .largeSubtitle) {
                factsLine
                    .padding(.top, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink {
                    NotificationsView(patientID: session.patientID)
                } label: {
                    Image(systemName: unreadCount > 0 ? "bell.badge" : "bell")
                        .foregroundStyle(Theme.brand)
                        // Rings when something new arrives.
                        .symbolEffect(.wiggle, value: unreadCount)
                }
                .accessibilityLabel(unreadCount > 0 ? "Notices, \(unreadCount) unread" : "Notices")
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
        .sheet(isPresented: $showsMRN) {
            if let mrn {
                MRNSheet(mrn: mrn, name: displayName)
            }
        }
        .task(id: session.patientID) { await load() }
        // Back from the background: reload quietly. The cache answers if the
        // data is under five minutes old; otherwise this fetches fresh data.
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await load(showsPlaceholders: false) } }
        }
    }

    // MARK: - Pinned sections

    @ViewBuilder
    private func section(_ section: HomeSection) -> some View {
        switch section {
        case .upcoming: upcomingSection
        case .results: resultsSection
        case .medication: medicationSection
        case .immunisations: immunisationSection
        case .growth: GrowthHomeSection()
        case .goals: HealthGoalsSection()
        case .sharing: sharingCard
        case .explore: exploreMoreSection
        }
    }

    // MARK: - Header (diagnosis + allergy pills)

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            if isLoading {
                HStack(spacing: 10) {
                    ForEach(["Placeholder", "Placeholder issue", "Allergy"], id: \.self) { text in
                        healthChip(text, systemImage: "heart.text.square.fill", color: Theme.brand)
                    }
                }
                .redacted(reason: .placeholder)
            } else {
                NavigationLink(value: Feature.healthSummary) {
                    // Discover's category chips, wrapping rather than scrolling.
                    FlowLayout(spacing: 10) {
                        ForEach(issues) { issue in
                            // Grey icon, so the allergy chips are the ones that stand out.
                            healthChip(issue.name, systemImage: "heart.text.square.fill", color: .secondary)
                        }
                        if allergies.isEmpty {
                            healthChip("No known allergies", systemImage: "checkmark", color: Theme.green)
                        } else {
                            ForEach(allergies) { allergy in
                                healthChip(allergy.substance, systemImage: "allergens", color: Theme.red)
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

    /// A diagnosis or allergy, styled like Discover's categories in the
    /// grouped card colour (the default grey vanishes on Home's background).
    private func healthChip(_ title: String, systemImage: String, color: Color) -> some View {
        CategoryChip(title: title, systemImage: systemImage, color: color,
                     background: Color(.secondarySystemGroupedBackground))
    }

    /// Full name for the UR sheet.
    private var displayName: String {
        fullName ?? session.activeAccount?.name ?? profile.fullName
    }

    /// `factsLine` as plain text, for the collapsed title's subtitle.
    private var factsText: String {
        [session.activeAccount?.dateOfBirth?.ageDescription, mrn.map { "UR \($0)" }]
            .compactMap(\.self)
            .joined(separator: " · ")
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
                    .accessibilityLabel("UR number, \(spokenDigits(mrn))")
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
                emptyCard("No upcoming visits", systemImage: "calendar.badge.checkmark",
                          detail: "Appointments booked with the hospital appear here, with the time and where to go.")
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
                emptyCard("No test results yet", systemImage: "testtube.2",
                          detail: "Results appear here once the lab releases them to the portal. Some take a few days.")
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
                emptyCard("No current medication", systemImage: "pills",
                          detail: "Medication prescribed by the hospital appears here, with reminders you can set.")
            } else {
                NavigationLink(value: Feature.medication) {
                    MedicationSummaryCard(medications: medications)
                }
                .buttonStyle(.plain)
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
                emptyCard("No immunisations on file", systemImage: "syringe",
                          detail: "Vaccines recorded by the hospital appear here. Ones given elsewhere may not be listed.")
            } else {
                NavigationLink(value: Feature.immunisations) {
                    ImmunisationSummaryCard(groups: immunisations)
                }
                .buttonStyle(.plain)
            }
        }
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

    /// Health-style sharing card: picture, what it does, and a button.
    private var sharingCard: some View {
        let art = Feature.sharing.tileArt
        return VStack(alignment: .leading, spacing: 10) {
            Image(systemName: "person.2.wave.2.fill")
                .symbolRenderingMode(.palette)
                .foregroundStyle(art.color, art.color.lighter)
                .font(.system(size: 36))
            Text("Share a Health Summary")
                .font(.headline)
            Text("Make a PDF of allergies, conditions and medication for a GP, school or carer. You choose what goes in.")
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
            NavigationLink(value: Feature.sharing) {
                Text("Create Summary")
                    .font(.subheadline.weight(.semibold))
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
            .tint(Theme.brand)
            .padding(.top, 4)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: Theme.cardRadius))
    }

    // MARK: - Building blocks

    private func listSkeleton(rows: Int) -> some View {
        VStack(spacing: 0) {
            ForEach(0..<rows, id: \.self) { index in
                ListRowSkeleton()
                if index < rows - 1 { Divider().padding(.leading, 68) }
            }
        }
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: Theme.cardRadius))
    }

    /// Health-style empty state: what's missing, and what will appear here.
    private func emptyCard(_ text: String, systemImage: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: systemImage)
                .font(.title3)
                .foregroundStyle(Theme.brand)
            VStack(alignment: .leading, spacing: 2) {
                Text(text)
                    .font(.subheadline.weight(.semibold))
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
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
        let allMedications = await medicationsTask ?? []
        medications = allMedications.filter(\.isActive)
        issues = await issuesTask ?? []
        let header = await headerTask
        mrn = header?.urNumber
        fullName = header?.fullName
        // Matches this child and their medications with another parent's
        // phone (by UR number and medicine name) for shared reminders.
        if let ur = header?.urNumber {
            medicationStore.linkForSharing(patientID: id, urNumber: ur,
                                           medications: allMedications.map { ($0.id, $0.sharingName) })
        }
        allergies = await allergiesTask ?? []
        immunisations = ImmunisationGroup.group(await immunisationsTask ?? [])
        explore = await exploreTask

        upcoming = appointments
            .filter { $0.status == .scheduled }
            .sorted { $0.date < $1.date }
        unreadMessages = messages.filter(\.isUnread).count
        unreadCount = unreadMessages + results.filter(\.isUnread).count

        isLoading = false
        updateWidgets()
    }

    // MARK: - Widgets

    /// Hands the widgets, controls and Live Activities this child's portal
    /// details. Doses come from the medication store directly.
    private func updateWidgets() {
        let visit = upcoming.first.map {
            WidgetSnapshot.Visit(id: $0.id, title: $0.title, department: $0.department, date: $0.date,
                                 isTelehealth: $0.isTelehealth, location: $0.checkInLocation ?? $0.address)
        }
        WidgetPublisher.shared.updateChild(
            id: session.patientID, name: session.activeAccount?.name ?? profile.preferredName,
            urNumber: mrn, nextVisit: visit,
            allergies: allergies.map { WidgetSnapshot.Allergy(substance: $0.substance, reaction: $0.reaction) },
            unreadMessages: unreadMessages, newResults: results.filter(\.isUnread).count)
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
    @State private var copied = false

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
                    .accessibilityLabel(spokenDigits(mrn))
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
        .fullBrightness()
    }
}

/// The next visit, Health-style: "Visit" in the Visits colour with the day
/// at the top, then what it is, where, and when.
struct UpcomingAppointmentCard: View {
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
                let organisms = (detailed ?? result).components.compactMap(\.organism)
                if !organisms.isEmpty {
                    // A culture: what grew, with the colony-count meter.
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(Array(organisms.prefix(3).enumerated()), id: \.offset) { _, organism in
                            OrganismRow(organism: organism)
                        }
                        if organisms.count > 3 {
                            Text("+\(organisms.count - 3) more")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.top, 2)
                } else {
                    HStack(alignment: .bottom) {
                        // What was tested rather than whether it was in range:
                        // a value outside the range isn't necessarily a worry,
                        // so the family opens the result to see it in context.
                        SpecimenPill(result: detailed ?? result)
                        Spacer(minLength: 8)
                        TrendSparkline(result: result)
                    }
                }
            }
        }
        .animation(.default, value: detailed?.specimen)
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
