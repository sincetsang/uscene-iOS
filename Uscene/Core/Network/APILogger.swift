import Foundation
import Observation

struct APILogEntry: Identifiable, Equatable {
    let id: UUID
    let startedAt: Date
    let durationMs: Int
    let method: String
    let url: String
    let requestHeaders: [String: String]
    let requestBody: String
    let statusCode: Int?
    let responseHeaders: [String: String]
    let responseBody: String
    let errorDescription: String?

    var isSuccess: Bool {
        guard let statusCode else { return errorDescription == nil }
        return (200...299).contains(statusCode) && errorDescription == nil
    }
}

@Observable
@MainActor
final class APILogStore {
    static let shared = APILogStore()

    private(set) var entries: [APILogEntry] = []
    private let maxEntries = 100

    func append(_ entry: APILogEntry) {
        entries.insert(entry, at: 0)
        if entries.count > maxEntries {
            entries = Array(entries.prefix(maxEntries))
        }
    }

    func clear() {
        entries.removeAll()
    }
}

enum APILogger {
    static var isEnabled: Bool {
        #if DEBUG
        true
        #else
        UserDefaults.standard.bool(forKey: "api_logger_enabled")
        #endif
    }

    static func log(
        method: String,
        url: URL,
        requestHeaders: [String: String],
        requestBody: Data?,
        response: HTTPURLResponse?,
        responseData: Data?,
        error: Error?,
        startedAt: Date
    ) {
        guard isEnabled else { return }

        let durationMs = Int(Date().timeIntervalSince(startedAt) * 1000)
        let requestBodyText = prettyBody(from: requestBody, contentType: requestHeaders["Content-Type"])
        let responseBodyText = prettyBody(from: responseData, contentType: response?.value(forHTTPHeaderField: "Content-Type"))
        let responseHeaders = dictionary(from: response?.allHeaderFields ?? [:])

        let entry = APILogEntry(
            id: UUID(),
            startedAt: startedAt,
            durationMs: durationMs,
            method: method,
            url: url.absoluteString,
            requestHeaders: requestHeaders,
            requestBody: requestBodyText,
            statusCode: response?.statusCode,
            responseHeaders: responseHeaders,
            responseBody: responseBodyText,
            errorDescription: error.map { ($0 as? LocalizedError)?.errorDescription ?? $0.localizedDescription }
        )

        Task { @MainActor in
            APILogStore.shared.append(entry)
        }

        // Full contiguous block so URL / headers / body / response stay together in the console.
        #if DEBUG
        print(formatBlock(entry))
        #endif
    }

    /// Single contiguous block so Xcode console keeps URL / headers / body / response together.
    private static func formatBlock(_ entry: APILogEntry) -> String {
        let stamp = isoFormatter.string(from: entry.startedAt)
        let status = entry.statusCode.map(String.init) ?? "—"
        let marker = entry.isSuccess ? "OK" : "FAIL"

        var lines: [String] = [
            "",
            "┌──────────────── API \(marker) ────────────────",
            "│ time     : \(stamp)",
            "│ duration : \(entry.durationMs) ms",
            "│ method   : \(entry.method)",
            "│ url      : \(entry.url)",
            "│ status   : \(status)",
            "├── Request Headers",
        ]

        if entry.requestHeaders.isEmpty {
            lines.append("│ (none)")
        } else {
            for key in entry.requestHeaders.keys.sorted() {
                lines.append("│ \(key): \(entry.requestHeaders[key] ?? "")")
            }
        }

        lines.append("├── Request Body")
        lines.append(contentsOf: indentBlock(entry.requestBody.isEmpty ? "(empty)" : entry.requestBody))

        lines.append("├── Response Headers")
        if entry.responseHeaders.isEmpty {
            lines.append("│ (none)")
        } else {
            for key in entry.responseHeaders.keys.sorted() {
                lines.append("│ \(key): \(entry.responseHeaders[key] ?? "")")
            }
        }

        lines.append("├── Response JSON")
        lines.append(contentsOf: indentBlock(entry.responseBody.isEmpty ? "(empty)" : entry.responseBody))

        if let errorDescription = entry.errorDescription, !errorDescription.isEmpty {
            lines.append("├── Error")
            lines.append(contentsOf: indentBlock(errorDescription))
        }

        lines.append("└──────────────────────────────────────────────")
        lines.append("")
        return lines.joined(separator: "\n")
    }

    private static func indentBlock(_ text: String) -> [String] {
        text.split(separator: "\n", omittingEmptySubsequences: false).map { "│ \($0)" }
    }

    private static func prettyBody(from data: Data?, contentType: String?) -> String {
        guard let data, !data.isEmpty else { return "" }

        if let contentType, contentType.lowercased().contains("multipart/form-data") {
            return "<multipart \(data.count) bytes>"
        }

        if let object = try? JSONSerialization.jsonObject(with: data),
           let pretty = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]),
           let text = String(data: pretty, encoding: .utf8) {
            return text
        }

        if let text = String(data: data, encoding: .utf8) {
            return text
        }

        return "<binary \(data.count) bytes>"
    }

    private static func dictionary(from headers: [AnyHashable: Any]) -> [String: String] {
        var result: [String: String] = [:]
        for (key, value) in headers {
            result[String(describing: key)] = String(describing: value)
        }
        return result
    }

    private static let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}
