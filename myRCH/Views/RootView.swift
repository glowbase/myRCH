import SwiftUI

/// Links from widgets, controls and Live Activities (`myrch://…`).
enum DeepLink: Equatable {
    /// The Medical ID page, at full brightness.
    case medicalID
    /// The logging sheet for a dose time.
    case dose(patientID: String, scheduled: Date)
    /// A visit's details (the next visit, when no id is given).
    case visit(id: String?)
    /// The Medication page.
    case medication
    /// Notifications: new results and messages.
    case whatsNew

    /// Also returns the child to switch to first, if the link names one.
    static func parse(_ url: URL) -> (DeepLink, child: String?)? {
        guard url.scheme == "myrch", let host = url.host() else { return nil }
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let child = items.first { $0.name == "child" }?.value
        switch host {
        case "medical-id":
            return (.medicalID, child)
        case "visit":
            return (.visit(id: items.first { $0.name == "id" }?.value), child)
        case "medication":
            return (.medication, child)
        case "whats-new":
            return (.whatsNew, child)
        case "dose":
            guard let patient = items.first(where: { $0.name == "patient" })?.value,
                  let stamp = items.first(where: { $0.name == "time" })?.value.flatMap(Double.init) else { return nil }
            return (.dose(patientID: patient, scheduled: Date(timeIntervalSince1970: stamp)), patient)
        default:
            return nil
        }
    }

    static func medicalIDURL(child: String?) -> URL? {
        var components = URLComponents(string: "myrch://medical-id")
        if let child { components?.queryItems = [URLQueryItem(name: "child", value: child)] }
        return components?.url
    }

    static func doseURL(patientID: String, time: Date) -> URL? {
        var components = URLComponents(string: "myrch://dose")
        components?.queryItems = [URLQueryItem(name: "patient", value: patientID),
                                  URLQueryItem(name: "time", value: String(time.timeIntervalSince1970))]
        return components?.url
    }
}

/// A screen opened from a link, shown as a sheet over whatever's open.
private enum LinkedScreen: Identifiable {
    case medicalID, visit(id: String?), medication, whatsNew

    var id: String {
        switch self {
        case .medicalID: "medical-id"
        case let .visit(id): "visit-\(id ?? "next")"
        case .medication: "medication"
        case .whatsNew: "whats-new"
        }
    }
}

/// Switches between the sign-in screen and the authenticated app.
struct RootView: View {
    @Environment(Session.self) private var session
    @Environment(MedicationStore.self) private var store
    @State private var linked: LinkedScreen?
    @State private var content = RCHContentStore.shared

    var body: some View {
        @Bindable var store = store
        switch session.phase {
        case .signedOut, .authenticating:
            if session.isRestoring {
                LaunchView()
            } else {
                LoginView()
            }
        case .verifyingCode:
            VerificationCodeView()
        case let .signedIn(profile):
            MainTabView(profile: profile)
                // A tapped medication reminder opens its logging sheet, on
                // top of whatever screen is showing.
                .sheet(item: $store.openSlot) { DoseLogSheet(slot: $0) }
                .sheet(item: $linked) { screen in
                    NavigationStack {
                        linkedView(screen)
                            .toolbar {
                                ToolbarItem(placement: .confirmationAction) {
                                    Button("Done") { linked = nil }
                                }
                            }
                    }
                }
                .onOpenURL { open($0, profile: profile) }
                // A tapped Discover alert opens its article.
                .sheet(item: $content.openLink) { link in
                    NavigationStack {
                        discoverView(link)
                            .toolbar {
                                ToolbarItem(placement: .confirmationAction) {
                                    Button("Done") { content.openLink = nil }
                                }
                            }
                    }
                }
        }
    }

    @ViewBuilder
    private func discoverView(_ link: RCHContentStore.Link) -> some View {
        switch link {
        case let .post(id):
            if let post = content.post(id: id) { NewsArticleView(post: post) } else { DiscoverView() }
        case let .sheet(url):
            if let sheet = content.sheet(url: url) { FactSheetArticleView(sheet: sheet) } else { DiscoverView() }
        }
    }

    private func open(_ url: URL, profile: PatientProfile) {
        guard let (link, child) = DeepLink.parse(url) else { return }
        // A widget set to another child switches to them first.
        if let child, profile.linkedAccounts.contains(where: { $0.id == child }) {
            session.activeAccountID = child
        }
        switch link {
        case .medicalID: linked = .medicalID
        case let .visit(id): linked = .visit(id: id)
        case .medication: linked = .medication
        case .whatsNew: linked = .whatsNew
        case let .dose(patientID, scheduled):
            linked = nil
            store.openSlot = MedicationStore.Slot(patientID: patientID, scheduled: scheduled)
        }
    }

    @ViewBuilder
    private func linkedView(_ screen: LinkedScreen) -> some View {
        switch screen {
        case .medicalID: MedicalIDView(patientID: session.patientID)
        case let .visit(id): LinkedVisitView(appointmentID: id)
        case .medication: MedicationsView(patientID: session.patientID)
        case .whatsNew: NotificationsView(patientID: session.patientID)
        }
    }
}

#Preview {
    RootView()
        .environment(Session())
        .environment(MedicationStore.shared)
}

/// A visit opened from a widget or Live Activity: finds it in the (cached)
/// appointments and shows its details, or the next visit if no id is given.
private struct LinkedVisitView: View {
    let appointmentID: String?
    @Environment(Session.self) private var session

    var body: some View {
        AsyncSection {
            try await session.service.appointments(for: session.patientID)
        } content: { appointments in
            let upcoming = appointments.filter { $0.status == .scheduled }.sorted { $0.date < $1.date }
            if let visit = appointments.first(where: { $0.id == appointmentID }) ?? upcoming.first {
                AppointmentDetailView(appointment: visit)
            } else {
                ContentUnavailableView("Visit not found", systemImage: "calendar.badge.exclamationmark",
                                       description: Text("It may have been moved or cancelled."))
            }
        }
    }
}
