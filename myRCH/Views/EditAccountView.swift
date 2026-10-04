import PhotosUI
import SwiftUI

/// The linked accounts, each opening its editor. Reached from Settings.
struct EditAccountsView: View {
    @Environment(Session.self) private var session

    /// Others' accounts only: like the portal's Family Access page, the
    /// signed-in person's own isn't customised here. Indices are kept for
    /// each account's fallback colour.
    private var accounts: [(offset: Int, element: LinkedAccount)] {
        guard let profile = session.profile else { return [] }
        return Array(profile.linkedAccounts.enumerated()).filter { $0.element.id != profile.id }
    }

    var body: some View {
        List {
            Section {
                ForEach(accounts, id: \.element.id) { index, account in
                    NavigationLink {
                        EditAccountView(account: account, index: index)
                    } label: {
                        HStack(spacing: 14) {
                            AccountAvatar(account: account, index: index, size: 34)
                            Text(account.name)
                        }
                    }
                }
            } footer: {
                Text("Nicknames, photos and colours are saved to the portal, so they show there too.")
            }
        }
        .navigationTitle("Nicknames and Photos")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Sets a linked account's nickname, photo and colour, like the portal's
/// Family Access page.
struct EditAccountView: View {
    let account: LinkedAccount
    /// Position in the list, for the fallback colour when none is set.
    let index: Int

    @Environment(Session.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var nickname: String
    @State private var colour: Int?
    @State private var photoItem: PhotosPickerItem?
    /// A newly chosen photo, ready to upload.
    @State private var newPhoto: (image: UIImage, jpeg: Data)?
    /// Remove Photo was chosen; cleared again by picking a new photo.
    @State private var removesPhoto = false
    @State private var confirmsRemovePhoto = false
    @State private var isSaving = false
    @State private var errorMessage: String?

    init(account: LinkedAccount, index: Int) {
        self.account = account
        self.index = index
        _nickname = State(initialValue: account.name)
        _colour = State(initialValue: account.tabColor)
    }

    private var tint: Color {
        colour.map { Theme.accountColours[$0] } ?? Theme.accountTint(account, at: index)
    }

    private var initials: String {
        let parts = nickname.split(separator: " ").prefix(2)
        let text = parts.compactMap(\.first).map(String.init).joined().uppercased()
        return text.isEmpty ? account.initials : text
    }

    private var trimmedNickname: String {
        nickname.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var hasChanges: Bool {
        trimmedNickname != account.name || colour != account.tabColor || photoChange != .keep
    }

    private var photoChange: AccountPhotoChange {
        if let newPhoto { return .replace(newPhoto.jpeg) }
        return removesPhoto ? .remove : .keep
    }

    var body: some View {
        let photo = newPhoto?.image ?? (removesPhoto ? nil : session.accountPhotos[account.id])
        // Worked out here: the picker's label closure is Sendable.
        let photoTitle = photo == nil ? "Add Photo" : "Change Photo"
        Form {
            Section {
                VStack(spacing: 12) {
                    AvatarView(initials: initials, tint: tint, size: 96, image: photo)
                    HStack(spacing: 12) {
                        PhotosPicker(selection: $photoItem, matching: .images) {
                            Text(photoTitle)
                                .font(.subheadline.weight(.semibold))
                        }
                        if photo != nil {
                            Button("Remove", role: .destructive) {
                                confirmsRemovePhoto = true
                            }
                            .font(.subheadline.weight(.semibold))
                        }
                    }
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.capsule)
                    .confirmationDialog("Remove this photo?", isPresented: $confirmsRemovePhoto,
                                        titleVisibility: .visible) {
                        Button("Remove Photo", role: .destructive) {
                            newPhoto = nil
                            photoItem = nil
                            removesPhoto = true
                        }
                    } message: {
                        Text("The portal shows initials instead, once you save.")
                    }
                }
                .frame(maxWidth: .infinity)
                .listRowBackground(Color.clear)
            }

            Section {
                TextField("Patient's own name", text: $nickname)
                    .textContentType(.nickname)
                    .submitLabel(.done)
            } header: {
                Text("Nickname")
            } footer: {
                Text("Leave blank to use the patient's own name.")
            }

            Section("Colour scheme") {
                colourPicker
            }
        }
        .navigationTitle(account.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                if isSaving {
                    ProgressView()
                } else {
                    Button("Save", action: save)
                        .disabled(!hasChanges)
                }
            }
        }
        .task(id: photoItem) { await preparePhoto() }
        .alert("Couldn't save", isPresented: .init(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    /// A row of swatches with a tick on the chosen one, as on the portal.
    private var colourPicker: some View {
        HStack(spacing: 0) {
            ForEach(Theme.accountColours.indices, id: \.self) { option in
                Button {
                    colour = option
                } label: {
                    Circle()
                        .fill(Theme.accountColours[option])
                        .frame(width: 36, height: 36)
                        .overlay {
                            if option == colour {
                                Image(systemName: "checkmark")
                                    .font(.body.weight(.bold))
                                    .foregroundStyle(.white)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Theme.accountColourNames[option])
                .accessibilityAddTraits(option == colour ? .isSelected : [])
            }
        }
        .padding(.vertical, 6)
    }

    /// Crops the chosen photo to a square and shrinks it, since it's only
    /// ever shown as a small circle. JPEG, as the portal's own upload sends.
    private func preparePhoto() async {
        guard let photoItem else { return }
        guard let data = try? await photoItem.loadTransferable(type: Data.self),
              let original = UIImage(data: data) else {
            errorMessage = "That photo couldn't be read."
            return
        }
        let side = min(original.size.width, original.size.height)
        let target = min(side, 512)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: CGSize(width: target, height: target), format: format).image { _ in
            let scale = target / side
            let drawn = CGSize(width: original.size.width * scale, height: original.size.height * scale)
            original.draw(in: CGRect(x: (target - drawn.width) / 2, y: (target - drawn.height) / 2,
                                     width: drawn.width, height: drawn.height))
        }
        guard let jpeg = image.jpegData(compressionQuality: 0.8) else {
            errorMessage = "That photo couldn't be read."
            return
        }
        newPhoto = (image, jpeg)
        removesPhoto = false
    }

    private func save() {
        // The portal needs a colour: its first (blue) if none was ever set.
        let chosen = colour ?? 0
        isSaving = true
        Task {
            defer { isSaving = false }
            do {
                try await session.customiseAccount(account.id, nickname: trimmedNickname,
                                                   colour: chosen, photo: photoChange)
                dismiss()
            } catch {
                errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
    }
}
