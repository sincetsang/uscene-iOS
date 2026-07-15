import Foundation
import Observation

@Observable
@MainActor
final class AuthStore {
    static let shared = AuthStore()

    private let accessKey = "access_token"
    private let refreshKey = "refresh_token"

    var accessToken: String?
    var refreshToken: String?
    var user: AppUser?
    var assets: [UserAsset] = []
    var auths: [UserAuthBinding] = []
    var userStat: UserStatRow?
    var isLoadingUser = false
    var lastError: String?

    var isLoggedIn: Bool {
        !(accessToken ?? "").isEmpty
    }

    func balance(for currency: String) -> String {
        assets.first { ($0.currency ?? "").uppercased() == currency.uppercased() }?.displayBalance ?? "0"
    }

    private init() {
        syncFromKeychain()
    }

    func syncFromKeychain() {
        accessToken = KeychainStore.string(forKey: accessKey)
        refreshToken = KeychainStore.string(forKey: refreshKey)
    }

    func applyToken(_ token: TokenResponse) {
        accessToken = token.access_token
        refreshToken = token.refresh_token
        if let access = token.access_token {
            KeychainStore.set(access, forKey: accessKey)
        }
        if let refresh = token.refresh_token {
            KeychainStore.set(refresh, forKey: refreshKey)
        }
    }

    func loginWithEmail(email: String, captcha: String, inviteCode: String = "") async throws {
        let token = try await AuthAPI.emailLogin(email: email, captcha: captcha, inviteCode: inviteCode)
        applyToken(token)
        try await refreshUser()
    }

    func loginWithApple(idToken: String, inviteCode: String = "") async throws {
        let token = try await AuthAPI.appleLogin(idToken: idToken, inviteCode: inviteCode)
        applyToken(token)
        try await refreshUser()
    }

    func loginWithGoogle(idToken: String, inviteCode: String = "") async throws {
        let token = try await AuthAPI.googleLogin(idToken: idToken, inviteCode: inviteCode)
        applyToken(token)
        try await refreshUser()
    }

    func refreshUser() async throws {
        guard isLoggedIn else {
            user = nil
            assets = []
            auths = []
            userStat = nil
            return
        }
        isLoadingUser = true
        defer { isLoadingUser = false }
        let profile = try await AuthAPI.userInfo()
        user = profile.user
        assets = profile.user_assets ?? []
        auths = profile.user_auths ?? []
        userStat = profile.user_stat?.first
    }

    func bootstrap() async {
        guard isLoggedIn else { return }
        do {
            try await refreshUser()
        } catch {
            lastError = error.localizedDescription
        }
    }

    func logout() {
        accessToken = nil
        refreshToken = nil
        user = nil
        assets = []
        auths = []
        userStat = nil
        KeychainStore.remove(forKey: accessKey)
        KeychainStore.remove(forKey: refreshKey)
    }
}
