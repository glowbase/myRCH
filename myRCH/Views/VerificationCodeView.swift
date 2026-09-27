import SwiftUI

/// Second sign-in step, shown when the portal asks for a one-time code
/// (Authentication/SecondaryValidation). First pick where to send the code,
/// then enter it.
struct VerificationCodeView: View {
    @Environment(Session.self) private var session

    @State private var code = ""
    @State private var rememberDevice = true
    @FocusState private var codeFocused: Bool

    private let controlHeight: CGFloat = 52
    private let controlRadius: CGFloat = 14

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                header
                    .padding(.top, 72)

                if let sentVia = session.codeSentVia {
                    codeEntry(sentVia: sentVia)
                } else {
                    deliveryChoice
                }

                if let error = session.verificationError {
                    Label(error, systemImage: "exclamationmark.circle.fill")
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                Button("Cancel", role: .cancel) {
                    session.cancelVerification()
                }
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Theme.brandText)
                .disabled(session.isVerifying)
            }
            .padding(.horizontal, 24)
            .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Theme.welcomeBackground.ignoresSafeArea())
        .tint(Theme.brand)
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 12) {
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 44))
                .foregroundStyle(Theme.brand)
                .accessibilityHidden(true)
            Text("Verify it's you")
                .font(.title2.weight(.bold))
                .foregroundStyle(Theme.ink)
            Text(session.codeSentVia == nil
                 ? "For your security, the portal needs a one-time code. Where should we send it?"
                 : "Enter the code we just sent you.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    // MARK: - Step 1: choose delivery

    private var deliveryChoice: some View {
        VStack(spacing: 12) {
            deliveryButton("Email me a code", systemImage: "envelope.fill", delivery: .email)
            deliveryButton("Text me a code", systemImage: "message.fill", delivery: .sms)
        }
    }

    private func deliveryButton(_ title: String, systemImage: String,
                                delivery: MyChartWebService.CodeDelivery) -> some View {
        Button {
            Task { await session.sendVerificationCode(via: delivery) }
        } label: {
            Label(title, systemImage: systemImage)
                .fontWeight(.semibold)
                .frame(maxWidth: .infinity)
                .frame(height: controlHeight)
                .foregroundStyle(Theme.brandText)
                .background(Theme.fieldBackground, in: .rect(cornerRadius: controlRadius, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: controlRadius, style: .continuous)
                        .strokeBorder(Theme.hairline)
                }
                .shadow(color: .black.opacity(0.06), radius: 8, y: 3)
        }
        .buttonStyle(.plain)
        .disabled(session.isVerifying)
    }

    // MARK: - Step 2: enter code

    private func codeEntry(sentVia: MyChartWebService.CodeDelivery) -> some View {
        VStack(spacing: 16) {
            TextField("6-digit code", text: $code)
                .textContentType(.oneTimeCode)
                .keyboardType(.numberPad)
                .font(.title3.monospacedDigit())
                .multilineTextAlignment(.center)
                .focused($codeFocused)
                .padding(.horizontal, 14)
                .frame(height: controlHeight)
                .background(Theme.fieldBackground, in: .rect(cornerRadius: controlRadius, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: controlRadius, style: .continuous)
                        .strokeBorder(codeFocused ? Theme.brand : Theme.hairline,
                                      lineWidth: codeFocused ? 1.5 : 1)
                }
                .onAppear { codeFocused = true }
                .onChange(of: code) { _, newValue in
                    // Digits only, as the portal's CodeEntrySettings require.
                    let digits = newValue.filter(\.isNumber)
                    if digits != newValue { code = digits }
                }

            Toggle("Remember this device", isOn: $rememberDevice)
                .font(.subheadline)
                .toggleStyle(.switch)

            verifyButton

            Button("Send a new code") {
                code = ""
                Task { await session.sendVerificationCode(via: sentVia) }
            }
            .font(.subheadline.weight(.medium))
            .disabled(session.isVerifying)
        }
    }

    private var verifyButton: some View {
        let isReady = !code.isEmpty && !session.isVerifying
        return Button {
            codeFocused = false
            Task { await session.verifyCode(code, rememberDevice: rememberDevice) }
        } label: {
            HStack(spacing: 8) {
                if session.isVerifying {
                    ProgressView().tint(.white)
                } else {
                    Text("Verify").fontWeight(.semibold)
                    Image(systemName: "arrow.right")
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: controlHeight)
            .foregroundStyle(.white)
            .background {
                RoundedRectangle(cornerRadius: controlRadius, style: .continuous)
                    .fill(isReady
                          ? AnyShapeStyle(LinearGradient(colors: [Theme.brand, Theme.brandDeep],
                                                         startPoint: .leading, endPoint: .trailing))
                          : AnyShapeStyle(Theme.brandDisabled))
            }
        }
        .buttonStyle(.plain)
        .disabled(!isReady)
    }
}

#Preview {
    VerificationCodeView()
        .environment(Session())
}
