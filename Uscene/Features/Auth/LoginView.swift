import SwiftUI
import AuthenticationServices

struct LoginView: View {
    @Environment(LanguageManager.self) private var language
    @Environment(AuthStore.self) private var auth
    @Environment(\.dismiss) private var dismiss

    @State private var email = ""
    @State private var code = ""
    @State private var inviteCode = ""
    @State private var isSendingCode = false
    @State private var isLoggingIn = false
    @State private var countdown = 0
    @State private var errorMessage: String?
    @State private var timer: Timer?

    var body: some View {
        Form {
            Section {
                TextField(language.t("login.email"), text: $email)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.emailAddress)
                    .autocorrectionDisabled()

                HStack {
                    TextField(language.t("login.code"), text: $code)
                        .keyboardType(.numberPad)
                    Button {
                        Task { await sendCode() }
                    } label: {
                        if isSendingCode {
                            ProgressView()
                        } else if countdown > 0 {
                            Text("\(countdown)s")
                        } else {
                            Text(language.t("login.sendCode"))
                        }
                    }
                    .disabled(isSendingCode || countdown > 0 || email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }

                TextField(language.t("login.inviteCode"), text: $inviteCode)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }

            Section {
                Button {
                    Task { await loginEmail() }
                } label: {
                    if isLoggingIn {
                        ProgressView().frame(maxWidth: .infinity)
                    } else {
                        Text(language.t("login.signIn"))
                            .frame(maxWidth: .infinity)
                    }
                }
                .disabled(isLoggingIn || email.isEmpty || code.isEmpty)

                SignInWithAppleButton(.signIn) { request in
                    request.requestedScopes = [.fullName, .email]
                } onCompletion: { result in
                    Task { await handleApple(result) }
                }
                .signInWithAppleButtonStyle(.black)
                .frame(height: 44)

                Button {
                    Task { await handleGoogle() }
                } label: {
                    HStack {
                        Image(systemName: "g.circle.fill")
                        Text(language.t("login.google"))
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                }
                .buttonStyle(.bordered)
            }

            if let errorMessage {
                Section {
                    Text(errorMessage).foregroundStyle(.red)
                }
            }

            Section {
                NavigationLink {
                    AppWebView(
                        title: language.t("login.privacyPolicy"),
                        url: AppConfig.privacyURL(language: language.language)
                    )
                } label: {
                    Text(language.t("login.privacyPolicy"))
                        .font(.footnote)
                        .foregroundStyle(Color.accentColor)
                }
            }
        }
        .navigationTitle(language.t("login.title"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(language.t("common.cancel")) { dismiss() }
            }
        }
        .onDisappear {
            timer?.invalidate()
        }
    }

    @MainActor
    private func sendCode() async {
        isSendingCode = true
        errorMessage = nil
        defer { isSendingCode = false }
        do {
            try await AuthAPI.sendEmailCaptcha(email: email.trimmingCharacters(in: .whitespacesAndNewlines))
            startCountdown()
        } catch let error as APIError {
            if case .business(let code, _) = error, code == 503 {
                errorMessage = language.t("login.emailUnavailable")
            } else {
                errorMessage = error.localizedDescription
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func loginEmail() async {
        isLoggingIn = true
        errorMessage = nil
        defer { isLoggingIn = false }
        do {
            try await auth.loginWithEmail(
                email: email.trimmingCharacters(in: .whitespacesAndNewlines),
                captcha: code.trimmingCharacters(in: .whitespacesAndNewlines),
                inviteCode: inviteCode.trimmingCharacters(in: .whitespacesAndNewlines)
            )
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func handleApple(_ result: Result<ASAuthorization, Error>) async {
        switch result {
        case .failure(let error):
            errorMessage = error.localizedDescription
        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                  let tokenData = credential.identityToken,
                  let idToken = String(data: tokenData, encoding: .utf8) else {
                errorMessage = language.t("common.error")
                return
            }
            isLoggingIn = true
            defer { isLoggingIn = false }
            do {
                try await auth.loginWithApple(
                    idToken: idToken,
                    inviteCode: inviteCode.trimmingCharacters(in: .whitespacesAndNewlines)
                )
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    @MainActor
    private func handleGoogle() async {
        isLoggingIn = true
        errorMessage = nil
        defer { isLoggingIn = false }
        do {
            let idToken = try await GoogleSignInHelper.signIn()
            try await auth.loginWithGoogle(
                idToken: idToken,
                inviteCode: inviteCode.trimmingCharacters(in: .whitespacesAndNewlines)
            )
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func startCountdown() {
        countdown = 60
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            Task { @MainActor in
                if countdown > 0 {
                    countdown -= 1
                } else {
                    timer?.invalidate()
                }
            }
        }
    }
}
