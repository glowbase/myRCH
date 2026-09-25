import SwiftUI

struct LoginView: View {
    @Environment(Session.self) private var session

    @State private var username = ""
    @State private var password = ""
    @State private var rememberUsername = true
    @State private var showPassword = false
    @FocusState private var focus: Field?

    private enum Field { case username, password }

    var body: some View {
        GeometryReader { geo in
            ScrollView {
                VStack(spacing: 0) {
                    hero
                        .padding(.top, 96)
                    Spacer(minLength: 28)
                    card
                    Spacer(minLength: 28)
                    footer
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 8)
                .frame(minHeight: geo.size.height)
                .frame(maxWidth: .infinity)
            }
            .scrollBounceBehavior(.basedOnSize)
            .scrollDismissesKeyboard(.interactively)
        }
        .background {
            Theme.welcomeBackground.ignoresSafeArea()
            DecorativeBlobs().ignoresSafeArea()
        }
        .tint(Theme.brand)
    }

    // MARK: - Hero

    private var hero: some View {
        VStack(spacing: 20) {
            Image("RCHLogo")
                .resizable()
                .scaledToFit()
                .frame(maxWidth: 130)
                .blendMode(.multiply)
                .accessibilityLabel("The Royal Children's Hospital Melbourne")

            Text("Your child’s care, together in one place.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    // MARK: - Credentials card

    private var card: some View {
        VStack(spacing: 20) {
            VStack(spacing: 14) {
                fieldRow(icon: "person.fill", title: "Username") {
                    TextField("Enter your username", text: $username)
                        .textContentType(.username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($focus, equals: .username)
                        .submitLabel(.next)
                        .onSubmit { focus = .password }
                }

                fieldRow(icon: "lock.fill", title: "Password") {
                    passwordField
                }
            }

            HStack {
                Toggle("Remember me", isOn: $rememberUsername)
                    .toggleStyle(.switch)
                    .labelsHidden()
                Text("Remember me")
                    .font(.subheadline)
                Spacer()
                Link("Forgot details?", destination: URL(string: "https://myrchportal.rch.org.au")!)
                    .font(.subheadline.weight(.medium))
            }

            if let error = session.signInError {
                Label(error, systemImage: "exclamationmark.circle.fill")
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .transition(.opacity)
            }

            signInButton
                .padding(.top, 12)
        }
    }

    private var passwordField: some View {
        HStack {
            Group {
                if showPassword {
                    TextField("Enter your password", text: $password)
                } else {
                    SecureField("Enter your password", text: $password)
                }
            }
            .textContentType(.password)
            .focused($focus, equals: .password)
            .submitLabel(.go)
            .onSubmit { submit() }

            Button {
                showPassword.toggle()
            } label: {
                Image(systemName: showPassword ? "eye.slash.fill" : "eye.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(showPassword ? "Hide password" : "Show password")
        }
    }

    private func fieldRow<Content: View>(
        icon: String, title: String, @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .foregroundStyle(Theme.brand)
                    .frame(width: 22)
                content()
            }
            .padding(.vertical, 14)
            .padding(.horizontal, 14)
            .background(.background.secondary, in: .rect(cornerRadius: 14, style: .continuous))
        }
    }

    private var signInButton: some View {
        Button {
            submit()
        } label: {
            HStack(spacing: 8) {
                if session.isAuthenticating {
                    ProgressView().tint(.white)
                } else {
                    Text("Log in").fontWeight(.semibold)
                    Image(systemName: "arrow.right")
                }
            }
            .frame(maxWidth: .infinity, minHeight: 44)
            .foregroundStyle(.white)
            .padding(.vertical, 12)
            .background(
                LinearGradient(colors: [Theme.brand, Theme.brandDeep],
                               startPoint: .leading, endPoint: .trailing),
                in: .rect(cornerRadius: 16, style: .continuous))
            .shadow(color: Theme.brand.opacity(0.4), radius: 12, y: 6)
        }
        .buttonStyle(.plain)
        .disabled(session.isAuthenticating || username.isEmpty || password.isEmpty)
        .opacity(username.isEmpty || password.isEmpty ? 0.6 : 1)
        .animation(.easeInOut(duration: 0.2), value: session.isAuthenticating)
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 28) {
            footerLink("Need help?", systemImage: "questionmark.circle")
            footerLink("Sign up", systemImage: "person.badge.plus")
        }
    }

    private func footerLink(_ title: String, systemImage: String) -> some View {
        Link(destination: URL(string: "https://myrchportal.rch.org.au")!) {
            Label(title, systemImage: systemImage)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Theme.brandDeep)
        }
    }

    // MARK: - Actions

    private func submit() {
        guard !username.isEmpty, !password.isEmpty else { return }
        focus = nil
        Task { await session.signIn(username: username, password: password) }
    }
}

/// Soft, blurred accent shapes that drift slowly around the screen, adding a
/// playful children's-hospital warmth behind entry screens without distracting
/// from the form.
private struct DecorativeBlobs: View {
    private struct Blob {
        var color: Color
        var size: CGFloat
        var base: CGPoint      // fractional home position (0...1)
        var phase: Double      // offsets each blob's motion so they don't sync
    }

    private let blobs: [Blob] = [
        Blob(color: Theme.yellow, size: 160, base: CGPoint(x: 0.15, y: 0.12), phase: 0.0),
        Blob(color: Theme.teal,   size: 200, base: CGPoint(x: 0.88, y: 0.18), phase: 1.3),
        Blob(color: Theme.red,    size: 150, base: CGPoint(x: 0.90, y: 0.80), phase: 2.6),
        Blob(color: Theme.orange, size: 140, base: CGPoint(x: 0.22, y: 0.68), phase: 3.9),
        Blob(color: Theme.green,  size: 180, base: CGPoint(x: 0.10, y: 0.90), phase: 5.2)
    ]

    var body: some View {
        TimelineView(.animation) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            GeometryReader { geo in
                let w = geo.size.width
                let h = geo.size.height
                ZStack {
                    ForEach(Array(blobs.enumerated()), id: \.offset) { _, blob in
                        let x = blob.base.x * w + CGFloat(sin(t * 0.45 + blob.phase)) * w * 0.22
                        let y = blob.base.y * h + CGFloat(cos(t * 0.35 + blob.phase * 1.2)) * h * 0.16
                        Circle()
                            .fill(blob.color.opacity(0.22))
                            .frame(width: blob.size, height: blob.size)
                            .blur(radius: 44)
                            .position(x: x, y: y)
                    }
                }
            }
        }
    }
}

#Preview {
    LoginView()
        .environment(Session())
}
