import Foundation

enum AppConfig {
    static let apiBaseURL = "https://api.test.uscene.ebunker.io"
    static let platform = "ios.global"
    static let authorizationPrefix = "supermap"
    /// From RN `.env.development` GOOGLE_CLIENT_ID_IOS
    static let googleClientID = "717254225743-lndus4rhqn6spcg0hntkgcl3igea2jfv.apps.googleusercontent.com"
    /// Reown Cloud project id (same as Expo AppKit)
    static let walletConnectProjectId = "acf25adcb4cb089141a0052c1782ab10"
    static let walletRedirectUniversal = "https://uscene.com"
    static let walletRedirectNative = "uscene://"
    static let landRewardRiveURL = "https://telegram-heyo-app.web.app/static/animation/land.riv"
    static let likeRiveURL = "https://telegram-heyo-app.web.app/static/animation/rive-like.riv"
    /// UE Pay merchant label / return scheme (from Expo Android `yxhmap`)
    static let ueStoreName = "优享派"
    static let ueStoreLogo = "https://boring-test.web.app/favicon.ico"
    static let ueScheme = "yxhmap"
    static let ueMerchantTag = "yxhmap"

    static var isTestAPI: Bool {
        apiBaseURL.contains("test")
    }

    /// Sepolia when using test API; else Ethereum mainnet.
    static var ethChainId: Int {
        isTestAPI ? 11_155_111 : 1
    }

    static var usdtContractAddress: String {
        isTestAPI
            ? "0x2dF9E1073BB30E553E01F02F01f4069EAf5fbD6d"
            : "0xdAC17F958D2ee523a2206206994597C13D831ec7"
    }

    static var googleReversedClientID: String {
        let prefix = googleClientID.replacingOccurrences(of: ".apps.googleusercontent.com", with: "")
        return "com.googleusercontent.apps.\(prefix)"
    }

    static var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    }

    static var v1Host: URL {
        URL(string: "\(apiBaseURL)/api/v1")!
    }

    static var v2Host: URL {
        URL(string: "\(apiBaseURL)/api/v2")!
    }

    static func privacyURL(language: AppLanguage) -> URL {
        let locale = language == .english ? "en" : "zh"
        return URL(string: "https://cdn.uscene.co/static/private-\(locale).html")!
    }
}
