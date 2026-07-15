import SwiftUI
import UIKit

struct NetworkLogListView: View {
    @Environment(LanguageManager.self) private var language
    @State private var store = APILogStore.shared

    var body: some View {
        List {
            if store.entries.isEmpty {
                ContentUnavailableView(
                    language.t("networkLog.empty"),
                    systemImage: "antenna.radiowaves.left.and.right",
                    description: Text(language.t("networkLog.emptyHint"))
                )
            } else {
                ForEach(store.entries) { entry in
                    NavigationLink {
                        NetworkLogDetailView(entry: entry)
                    } label: {
                        NetworkLogRow(entry: entry)
                    }
                }
            }
        }
        .navigationTitle(language.t("networkLog.title"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(language.t("networkLog.clear")) {
                    store.clear()
                }
                .disabled(store.entries.isEmpty)
            }
        }
    }
}

private struct NetworkLogRow: View {
    let entry: APILogEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(entry.method)
                    .font(.caption.weight(.bold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(entry.isSuccess ? Color.green.opacity(0.15) : Color.red.opacity(0.15))
                    .foregroundStyle(entry.isSuccess ? Color.green : Color.red)
                    .clipShape(RoundedRectangle(cornerRadius: 4))

                Text(statusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                Text("\(entry.durationMs) ms")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Text(entry.url)
                .font(.footnote)
                .lineLimit(2)
                .foregroundStyle(.primary)
        }
        .padding(.vertical, 2)
    }

    private var statusText: String {
        if let code = entry.statusCode {
            return "HTTP \(code)"
        }
        return entry.errorDescription ?? "Error"
    }
}

struct NetworkLogDetailView: View {
    let entry: APILogEntry

    var body: some View {
        ScrollView {
            Text(detailText)
                .font(.system(.footnote, design: .monospaced))
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
                .padding()
        }
        .background(Color(.secondarySystemBackground))
        .navigationTitle(entry.method)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                ShareLink(item: detailText) {
                    Image(systemName: "square.and.arrow.up")
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    UIPasteboard.general.string = detailText
                } label: {
                    Image(systemName: "doc.on.doc")
                }
            }
        }
    }

    private var detailText: String {
        var lines: [String] = [
            "[\(entry.method)] \(entry.url)",
            "time: \(entry.startedAt.formatted(date: .abbreviated, time: .standard))",
            "duration: \(entry.durationMs) ms",
            "status: \(entry.statusCode.map(String.init) ?? "—")",
            "",
            "── Request Headers ──",
        ]

        if entry.requestHeaders.isEmpty {
            lines.append("(none)")
        } else {
            for key in entry.requestHeaders.keys.sorted() {
                lines.append("\(key): \(entry.requestHeaders[key] ?? "")")
            }
        }

        lines.append("")
        lines.append("── Request Body ──")
        lines.append(entry.requestBody.isEmpty ? "(empty)" : entry.requestBody)
        lines.append("")
        lines.append("── Response Headers ──")
        if entry.responseHeaders.isEmpty {
            lines.append("(none)")
        } else {
            for key in entry.responseHeaders.keys.sorted() {
                lines.append("\(key): \(entry.responseHeaders[key] ?? "")")
            }
        }
        lines.append("")
        lines.append("── Response JSON ──")
        lines.append(entry.responseBody.isEmpty ? "(empty)" : entry.responseBody)

        if let errorDescription = entry.errorDescription, !errorDescription.isEmpty {
            lines.append("")
            lines.append("── Error ──")
            lines.append(errorDescription)
        }

        return lines.joined(separator: "\n")
    }
}
