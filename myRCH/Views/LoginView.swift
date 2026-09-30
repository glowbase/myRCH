import SwiftUI

struct LoginView: View {
    @Environment(Session.self) private var session

    @State private var username = ""
    @State private var password = ""
    @State private var rememberUsername = true
    @State private var showPassword = false
    @State private var showsHelp = false
    @State private var showsSignUp = false
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
                // A tap on empty space closes the keyboard. Behind the
                // content, so the fields and buttons still get their taps.
                .background {
                    Color.clear
                        .contentShape(.rect)
                        .onTapGesture { focus = nil }
                }
            }
            .scrollBounceBehavior(.basedOnSize)
            .scrollDismissesKeyboard(.interactively)
        }
        .background(Theme.welcomeBackground.ignoresSafeArea())
        .tint(Theme.brand)
    }

    // MARK: - Hero

    private var hero: some View {
        VStack(spacing: 20) {
            // Transparent, with a white figure and wordmark in dark mode.
            Image("RCHLogo")
                .resizable()
                .scaledToFit()
                .frame(maxWidth: 130)
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
            footerButton("Need help?", systemImage: "questionmark.circle") { showsHelp = true }
            footerButton("Sign up", systemImage: "person.badge.plus") { showsSignUp = true }
        }
        .sheet(isPresented: $showsHelp) { PortalHelpView() }
        .sheet(isPresented: $showsSignUp) { SignUpFormView() }
    }

    private func footerButton(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
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

/// The launch screen's icon, the same size and place, on the same plain
/// white (black in dark mode), with anything else (a spinner, an unlock
/// button) below it so the icon never moves. Used while signing in at launch
/// and for the lock.
struct LaunchArtwork<Accessory: View>: View {
    /// Matches the 480px @3x `LaunchIcon` the launch screen shows.
    static var iconSize: CGFloat { 160 }
    @ViewBuilder var accessory: Accessory

    var body: some View {
        Image("LaunchIcon")
            .resizable()
            .scaledToFit()
            .frame(width: Self.iconSize, height: Self.iconSize)
            .accessibilityHidden(true)
            .overlay(alignment: .top) {
                accessory
                    .fixedSize()
                    .offset(y: Self.iconSize + 28)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            // The asset the launch screen uses, so the two match exactly.
            .background(Color("LaunchBackground").ignoresSafeArea())
    }
}

/// Shown while saved details sign in again at launch.
struct LaunchView: View {
    var body: some View {
        LaunchArtwork {
            ProgressView()
                .controlSize(.large)
                .accessibilityLabel("Signing in")
        }
    }
}

#Preview {
    LoginView()
        .environment(Session())
}
