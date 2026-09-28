import SwiftUI

/// Links from widgets, controls and Live Activities (`myrch://…`).
enum DeepLink: Equatable {
    /// The Medical ID page, at full brightness.
    case medicalID
    /// The logging sheet for a dose time.
    case dose(patientID: String, scheduled: Date)

    /// Also returns the child to switch to first, if the link names one.
    static func parse(_ url: URL) -> (DeepLink, child: String?)? {
        guard url.scheme == "myrch", let host = url.host() else { return nil }
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let child = items.first { $0.name == "child" }?.value
        switch host {
        case "medical-id":
            return (.medicalID, child)
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

/// Switches between the sign-in screen and the authenticated app.
struct RootView: View {
    @Environment(Session.self) private var session
    @Environment(MedicationStore.self) private var store
    @State private var showsMedicalID = false

    var body: some View {
        @Bindable var store = store
        switch session.phase {
        case .signedOut, .authenticating:
            LoginView()
        case .verifyingCode:
            VerificationCodeView()
        case let .signedIn(profile):
            MainTabView(profile: profile)
                // A tapped medication reminder opens its logging sheet, on
                // top of whatever screen is showing.
                .sheet(item: $store.openSlot) { DoseLogSheet(slot: $0) }
                .sheet(isPresented: $showsMedicalID) {
                    NavigationStack {
                        MedicalIDView(patientID: session.patientID)
                            .toolbar {
                                ToolbarItem(placement: .confirmationAction) {
                                    Button("Done") { showsMedicalID = false }
                                }
                            }
                    }
                }
                .onOpenURL { open($0, profile: profile) }
        }
    }

    private func open(_ url: URL, profile: PatientProfile) {
        guard let (link, child) = DeepLink.parse(url) else { return }
        // A widget set to another child switches to them first.
        if let child, profile.linkedAccounts.contains(where: { $0.id == child }) {
            session.activeAccountID = child
        }
        switch link {
        case .medicalID:
            showsMedicalID = true
        case let .dose(patientID, scheduled):
            store.openSlot = MedicationStore.Slot(patientID: patientID, scheduled: scheduled)
        }
    }
}

#Preview {
    RootView()
        .environment(Session())
        .environment(MedicationStore.shared)
}
