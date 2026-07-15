import SwiftUI
import UIKit

struct MyVerificationCodesView: View {
    @Environment(LanguageManager.self) private var language
    @Environment(AuthStore.self) private var auth

    @State private var filter = "all"
    @State private var codes: [VerificationCode] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var revealedIds: Set<Int> = []
    @State private var toastMessage: String?

    private var filters: [(String, String)] {
        [
            ("all", language.t("codes.filterAll")),
            ("unused", language.t("codes.filterUnused")),
            ("used", language.t("codes.filterUsed")),
        ]
    }

    var body: some View {
        Group {
            if isLoading && codes.isEmpty {
                ProgressView(language.t("common.loading"))
            } else if let errorMessage, codes.isEmpty {
                ContentUnavailableView {
                    Label(language.t("common.error"), systemImage: "exclamationmark.triangle")
                } description: {
                    Text(errorMessage)
                } actions: {
                    Button(language.t("common.retry")) { Task { await load() } }
                }
            } else if codes.isEmpty {
                ContentUnavailableView(language.t("codes.empty"), systemImage: "ticket")
            } else {
                List(codes) { code in
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text(language.t("codes.codeId"))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(revealedIds.contains(code.id) ? code.value : "*************")
                                .font(.headline.monospaced())
                            Button {
                                UIPasteboard.general.string = code.value
                                toastMessage = language.t("codes.copySuccess")
                            } label: {
                                Image(systemName: "doc.on.doc")
                            }
                            .buttonStyle(.borderless)
                            Button {
                                if revealedIds.contains(code.id) {
                                    revealedIds.remove(code.id)
                                } else {
                                    revealedIds.insert(code.id)
                                }
                            } label: {
                                Image(systemName: revealedIds.contains(code.id) ? "eye.slash" : "eye")
                            }
                            .buttonStyle(.borderless)
                        }

                        HStack {
                            Text(code.isUsed ? language.t("codes.filterUsed") : language.t("codes.filterUnused"))
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(code.isUsed ? .secondary : Color.accentColor)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 4)
                                        .stroke(code.isUsed ? Color.secondary.opacity(0.4) : Color.accentColor, lineWidth: 1)
                                )
                            Spacer()
                            if let created = code.created_at {
                                Text("\(language.t("codes.buyTime")) \(created)")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        if code.isUsed, let useTime = code.use_time {
                            Text("\(language.t("codes.verifyTime")) \(useTime)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle(language.t("codes.title"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                EmptyView()
            }
        }
        .safeAreaInset(edge: .top) {
            Picker("", selection: $filter) {
                ForEach(filters, id: \.0) { item in
                    Text(item.1).tag(item.0)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.bottom, 8)
            .background(.bar)
            .onChange(of: filter) { _, _ in
                Task { await load() }
            }
        }
        .overlay(alignment: .bottom) {
            if let toastMessage {
                Text(toastMessage)
                    .font(.caption)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.regularMaterial, in: Capsule())
                    .padding(.bottom, 24)
                    .transition(.opacity)
            }
        }
        .task { await load() }
        .refreshable { await load() }
        .onChange(of: toastMessage) { _, newValue in
            guard newValue != nil else { return }
            Task {
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                if toastMessage == newValue { toastMessage = nil }
            }
        }
    }

    @MainActor
    private func load() async {
        guard auth.isLoggedIn else {
            codes = []
            return
        }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            codes = try await UserAPI.verificationCodes(status: filter)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
