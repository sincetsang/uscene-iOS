import Foundation

/// Test API (`api.test.uscene.ebunker.io`) serves Traefik's self-signed default cert.
/// URLSession rejects it; trust only that known host (same setup that worked before
/// the HTTPTransport / IPv4 / DirectHTTPS experiments).
final class DevServerTrustDelegate: NSObject, URLSessionDelegate, URLSessionTaskDelegate {
    private let trustedHosts: Set<String> = [
        "api.test.uscene.ebunker.io"
    ]

    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        resolve(challenge, completionHandler: completionHandler)
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        resolve(challenge, completionHandler: completionHandler)
    }

    private func resolve(
        _ challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        let host = challenge.protectionSpace.host
        let method = challenge.protectionSpace.authenticationMethod

        guard method == NSURLAuthenticationMethodServerTrust,
              let trust = challenge.protectionSpace.serverTrust else {
            completionHandler(.performDefaultHandling, nil)
            return
        }

        let trusted = trustedHosts.contains(host)
            || trustedHosts.contains(where: { host == $0 || host.hasSuffix(".\($0)") })

        #if DEBUG
        print("[TLS] challenge host=\(host) trusted=\(trusted)")
        #endif

        if trusted {
            completionHandler(.useCredential, URLCredential(trust: trust))
        } else {
            completionHandler(.performDefaultHandling, nil)
        }
    }
}
