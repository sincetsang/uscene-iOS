import Foundation

enum APIError: LocalizedError {
    case http(Int)
    case business(code: Int, message: String)
    case decoding(Error)
    case unauthorized
    case network(Error)
    case cancelled
    case invalidURL
    case emptyData

    var isCancellation: Bool {
        if case .cancelled = self { return true }
        if case .network(let error) = self { return APIError.isCancellation(error) }
        return false
    }

    var errorDescription: String? {
        switch self {
        case .http(let code):
            return "Network error (\(code))"
        case .business(let code, let message):
            if code == 503 {
                // Backend mail / dependent service is down (verified on both test & prod).
                return message.isEmpty
                    ? "Email verification service is temporarily unavailable. Please try Sign in with Apple, or retry later."
                    : "\(message)\nEmail service is down on the server. Try Sign in with Apple, or retry later."
            }
            return message.isEmpty ? "Request failed (\(code))" : message
        case .decoding:
            return "Failed to parse response"
        case .unauthorized:
            return "Please sign in again"
        case .network(let error):
            return error.localizedDescription
        case .cancelled:
            return "cancelled"
        case .invalidURL:
            return "Invalid URL"
        case .emptyData:
            return "Empty response"
        }
    }

    static func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        if let urlError = error as? URLError, urlError.code == .cancelled { return true }
        let ns = error as NSError
        if ns.domain == NSURLErrorDomain, ns.code == NSURLErrorCancelled { return true }
        return false
    }
}
