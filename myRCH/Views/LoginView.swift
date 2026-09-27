import SwiftUI

struct LoginView: View {
    @Environment(Session.self) private var session
    @Environment(\.colorScheme) private var colorScheme

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
            // The logo is a JPEG with a white background. Multiply hides the
            // white on the light wash; on a dark background it would blacken
            // the whole logo, so there it sits on a white tile instead.
            Image("RCHLogo")
                .resizable()
                .scaledToFit()
                .frame(maxWidth: 130)
                .blendMode(colorScheme == .dark ? .normal : .multiply)
                .padding(colorScheme == .dark ? 12 : 0)
                .background(colorScheme == .dark ? Color.white : .clear,
                            in: .rect(cornerRadius: 20, style: .continuous))
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
                fieldRow(icon: "person.fill", title: "Username", field: .username) {
                    TextField("Enter your username", text: $username)
                        .textContentType(.username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($focus, equals: .username)
                        .submitLabel(.next)
                        .onSubmit { focus = .password }
                }

                fieldRow(icon: "lock.fill", title: "Password", field: .password) {
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

            #if DEBUG
            liveToggle
            #endif

            signInButton
                .padding(.top, 12)
        }
    }

    #if DEBUG
    /// Developer switch between mock data and the real portal.
    private var liveToggle: some View {
        @Bindable var session = session
        return Toggle(isOn: $session.useLivePortal) {
            Label("Connect to live RCH portal", systemImage: "antenna.radiowaves.left.and.right")
                .font(.subheadline)
        }
        .toggleStyle(.switch)
    }
    #endif

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

    /// Shared height and corner radius so the inputs and Log in button line up.
    private let controlHeight: CGFloat = 52
    private let controlRadius: CGFloat = 14

    private func fieldRow<Content: View>(
        icon: String, title: String, field: Field, @ViewBuilder content: () -> Content
    ) -> some View {
        let isFocused = focus == field
        return VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.bold))
                .foregroundStyle(Theme.ink.opacity(0.75))
                .textCase(.uppercase)
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .foregroundStyle(Theme.brand)
                    .frame(width: 22)
                content()
            }
            .padding(.horizontal, 14)
            .frame(height: controlHeight)
            .background(Theme.fieldBackground, in: .rect(cornerRadius: controlRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: controlRadius, style: .continuous)
                    .strokeBorder(isFocused ? Theme.brand : Theme.hairline,
                                  lineWidth: isFocused ? 1.5 : 1)
            }
            .shadow(color: .black.opacity(0.06), radius: 8, y: 3)
            .animation(.easeInOut(duration: 0.15), value: isFocused)
        }
    }

    private var signInButton: some View {
        let isReady = !username.isEmpty && !password.isEmpty
        return Button {
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
            .frame(maxWidth: .infinity)
            .frame(height: controlHeight)
            .foregroundStyle(.white)
            .background {
                // Solid colours in both states so the background never bleeds through.
                RoundedRectangle(cornerRadius: controlRadius, style: .continuous)
                    .fill(isReady
                          ? AnyShapeStyle(LinearGradient(colors: [Theme.brand, Theme.brandDeep],
                                                         startPoint: .leading, endPoint: .trailing))
                          : AnyShapeStyle(Theme.brandDisabled))
            }
            .shadow(color: Theme.brand.opacity(isReady ? 0.4 : 0), radius: 12, y: 6)
        }
        .buttonStyle(.plain)
        .disabled(session.isAuthenticating || !isReady)
        .animation(.easeInOut(duration: 0.2), value: isReady)
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
                .foregroundStyle(Theme.brandText)
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
        Blob(color: Theme.yellow, size: 200, base: CGPoint(x: 0.15, y: 0.12), phase: 0.0),
        Blob(color: Theme.teal,   size: 240, base: CGPoint(x: 0.88, y: 0.18), phase: 1.3),
        Blob(color: Theme.red,    size: 190, base: CGPoint(x: 0.90, y: 0.80), phase: 2.6),
        Blob(color: Theme.orange, size: 180, base: CGPoint(x: 0.22, y: 0.68), phase: 3.9),
        Blob(color: Theme.green,  size: 220, base: CGPoint(x: 0.10, y: 0.90), phase: 5.2)
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
                            .fill(blob.color.opacity(0.55))
                            .frame(width: blob.size, height: blob.size)
                            .blur(radius: 36)
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
