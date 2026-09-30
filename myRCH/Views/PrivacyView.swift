import SwiftUI

/// Settings > Privacy: what myRCH keeps, where it goes, and what it never
/// does, in plain words. Keep in step with the code when data handling changes.
struct PrivacyView: View {
    var body: some View {
        List {
            Section {
                Text("myRCH has no accounts, advertising, analytics or tracking of its own. Your children's records go between your iPhone and My RCH Portal, and nowhere else unless you choose to share them.")
            }

            section("Signing In", symbol: "key.fill", color: .gray, """
                Your portal username and password are kept in your iPhone's Keychain and only sent to My RCH Portal, over an encrypted connection. They're deleted when you sign out.
                """)

            section("Your Records", symbol: "heart.text.clipboard.fill", color: .pink, """
                Appointments, results, letters and messages are loaded from My RCH Portal while you use the app. They're only kept on your iPhone if you turn on Save Data on This iPhone, and then for up to 5 minutes, encrypted while your iPhone is locked and never backed up.
                """)

            section("Medication Notes and Reminders", symbol: "pills.fill", color: Theme.medication, """
                Your notes, reminder times and dose log stay on this iPhone and are never sent to the portal. If you share reminders with another parent, they're synced through your iCloud account and only the people you invite can see them. Signing out doesn't remove them.
                """)

            section("Widgets, Watch and Live Activities", symbol: "applewatch", color: .indigo, """
                Widgets, your Apple Watch and Live Activities show a copy of your next visit, medications and what's new. It's removed when you sign out. Allergies only appear on the Lock Screen if you turn that on.
                """)

            section("Things You Choose to Share", symbol: "square.and.arrow.up.fill", color: .blue, """
                myRCH only uses your calendar when you add a visit to it, and your photos when you attach one to a message. A health summary is only shared when you send it.
                """)
        }
        .navigationTitle("Privacy")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func section(_ title: String, symbol: String, color: Color, _ text: String) -> some View {
        Section {
            Text(text)
        } header: {
            Label(title, systemImage: symbol)
                .foregroundStyle(color)
        }
    }
}

#Preview {
    NavigationStack { PrivacyView() }
}
