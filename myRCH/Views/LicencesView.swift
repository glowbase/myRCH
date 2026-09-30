import SwiftUI

/// Settings > Licences: that the hospital's name, logo and portal belong to
/// The Royal Children's Hospital, not to this app.
struct LicencesView: View {
    var body: some View {
        List {
            Section("The Royal Children's Hospital") {
                Text("The Royal Children's Hospital name and logo, and My RCH Portal, belong to The Royal Children's Hospital, Melbourne. myRCH uses them only to show which hospital and portal your records come from. myRCH doesn't own them and claims no rights to them.")
                Text("myRCH is an independent app. It isn't made, endorsed or supported by The Royal Children's Hospital.")
            }
            Section("Your Records") {
                Text("Appointments, results, letters and other records in myRCH come from My RCH Portal. The hospital's records are the official version.")
            }
        }
        .navigationTitle("Licences")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack { LicencesView() }
}
