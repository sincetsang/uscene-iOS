import AuthenticationServices
import SwiftUI
import UIKit

enum GoogleSignInHelper {
    @MainActor
    static func signIn() async throws -> String {
        let clientID = AppConfig.googleClientID
        let redirectURI = "\(AppConfig.googleReversedClientID):/oauth2redirect/google"
        var components = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: "openid email profile"),
            URLQueryItem(name: "include_granted_scopes", value: "true"),
            URLQueryItem(name: "access_type", value: "offline"),
            URLQueryItem(name: "prompt", value: "select_account")
        ]
        guard let authURL = components.url else { throw APIError.invalidURL }

        let callbackURL: URL = try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(
                url: authURL,
                callbackURLScheme: AppConfig.googleReversedClientID
            ) { url, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let url else {
                    continuation.resume(throwing: APIError.emptyData)
                    return
                }
                continuation.resume(returning: url)
            }
            session.presentationContextProvider = GoogleAuthPresenter.shared
            session.prefersEphemeralWebBrowserSession = true
            if !session.start() {
                continuation.resume(throwing: APIError.network(NSError(domain: "GoogleSignIn", code: -1)))
            }
        }

        guard
            let code = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)?
                .queryItems?
                .first(where: { $0.name == "code" })?
                .value
        else {
            throw APIError.emptyData
        }

        return try await exchangeCodeForIDToken(code: code, redirectURI: redirectURI, clientID: clientID)
    }

    private static func exchangeCodeForIDToken(code: String, redirectURI: String, clientID: String) async throws -> String {
        var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let body = [
            "code=\(code.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? code)",
            "client_id=\(clientID)",
            "redirect_uri=\(redirectURI.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? redirectURI)",
            "grant_type=authorization_code"
        ].joined(separator: "&")
        request.httpBody = Data(body.utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw APIError.http((response as? HTTPURLResponse)?.statusCode ?? 502)
        }
        struct TokenJSON: Decodable {
            let id_token: String?
            let access_token: String?
        }
        let token = try JSONDecoder().decode(TokenJSON.self, from: data)
        guard let idToken = token.id_token else { throw APIError.emptyData }
        return idToken
    }
}

final class GoogleAuthPresenter: NSObject, ASWebAuthenticationPresentationContextProviding {
    static let shared = GoogleAuthPresenter()

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first { $0.isKeyWindow } ?? ASPresentationAnchor()
    }
}
