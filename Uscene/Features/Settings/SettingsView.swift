import SwiftUI

struct SettingsView: View {
    @Environment(LanguageManager.self) private var language
    @Environment(AuthStore.self) private var auth
    @Environment(\.dismiss) private var dismiss

    @State private var ota: OTAInfo?
    @State private var otaError: String?
    @State private var isCheckingOTA = false
    @State private var showLogin = false
    @State private var showFeedback = false

    var body: some View {
        List {
            Section(language.t("settings.language")) {
                Button {
                    language.followSystemLanguage()
                } label: {
                    HStack {
                        Text(language.t("settings.followSystem"))
                            .foregroundStyle(.primary)
                        Spacer()
                        if !language.hasManualOverride {
                            Image(systemName: "checkmark")
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                }
                ForEach(AppLanguage.allCases) { lang in
                    Button {
                        language.setLanguage(lang)
                    } label: {
                        HStack {
                            Text(lang.displayName)
                                .foregroundStyle(.primary)
                            Spacer()
                            if language.hasManualOverride, language.language == lang {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(Color.accentColor)
                            }
                        }
                    }
                }
            }

            Section {
                if auth.isLoggedIn {
                    NavigationLink {
                        ProfileEditView()
                    } label: {
                        Label(language.t("settings.profile"), systemImage: "person.crop.circle")
                    }
                    NavigationLink {
                        MyAddressView()
                    } label: {
                        Label(language.t("settings.address"), systemImage: "mappin.and.ellipse")
                    }
                } else {
                    Button {
                        showLogin = true
                    } label: {
                        Label(language.t("settings.profile"), systemImage: "person.crop.circle")
                    }
                    Button {
                        showLogin = true
                    } label: {
                        Label(language.t("settings.address"), systemImage: "mappin.and.ellipse")
                    }
                }

                Button {
                    showFeedback = true
                } label: {
                    Label(language.t("settings.feedback"), systemImage: "envelope")
                }
            }

            Section(language.t("ota.title")) {
                LabeledContent(language.t("ota.current"), value: AppConfig.appVersion)
                if isCheckingOTA {
                    HStack {
                        ProgressView()
                        Text(language.t("ota.checking"))
                            .foregroundStyle(.secondary)
                    }
                } else if let ota {
                    if let version = ota.version {
                        LabeledContent(language.t("ota.latest"), value: version)
                    }
                    if ota.need_update == true {
                        Text(language.t("ota.needUpdate"))
                            .foregroundStyle(.orange)
                    } else {
                        Text(language.t("ota.upToDate"))
                            .foregroundStyle(.secondary)
                    }
                    if let notes = ota.release_notes, !notes.isEmpty {
                        Text(notes)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if let urlString = ota.download_url, let url = URL(string: urlString) {
                        Link(language.t("ota.openStore"), destination: url)
                    }
                } else if let otaError {
                    Text(otaError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                Button(language.t("ota.check")) {
                    Task { await checkOTA() }
                }
            }

            Section {
                NavigationLink {
                    NetworkLogListView()
                } label: {
                    Label(language.t("networkLog.title"), systemImage: "network")
                }
                NavigationLink {
                    AppWebView(
                        title: language.t("login.privacyPolicy"),
                        url: AppConfig.privacyURL(language: language.language)
                    )
                } label: {
                    Label(language.t("login.privacyPolicy"), systemImage: "doc.text")
                }
            }

            Section {
                LabeledContent("Version", value: AppConfig.appVersion)
                LabeledContent("API", value: AppConfig.apiBaseURL)
                    .font(.caption)
            }

            if auth.isLoggedIn {
                Section {
                    Button(role: .destructive) {
                        auth.logout()
                        dismiss()
                    } label: {
                        Text(language.t("login.logout"))
                            .frame(maxWidth: .infinity)
                    }
                }
            }
        }
        .navigationTitle(language.t("settings.title"))
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showLogin) {
            NavigationStack { LoginView() }
        }
        .sheet(isPresented: $showFeedback) {
            FeedbackSheet()
        }
        .task { await checkOTA() }
    }

    @MainActor
    private func checkOTA() async {
        isCheckingOTA = true
        otaError = nil
        defer { isCheckingOTA = false }
        do {
            ota = try await SystemAPI.otaLatest()
        } catch {
            otaError = error.localizedDescription
        }
    }
}

private struct FeedbackSheet: View {
    @Environment(LanguageManager.self) private var language
    @Environment(\.dismiss) private var dismiss

    @State private var report = ""
    @State private var showThanks = false

    private let maxLength = 300

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                Text(language.t("settings.feedbackDesc"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                TextField(language.t("settings.feedbackPlaceholder"), text: $report, axis: .vertical)
                    .lineLimit(5...10)
                    .padding(12)
                    .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10))
                    .onChange(of: report) { _, value in
                        if value.count > maxLength {
                            report = String(value.prefix(maxLength))
                        }
                    }

                Text("\(language.t("settings.feedbackMaxLength")) \(maxLength) \(language.t("common.character")) · \(report.count)/\(maxLength)")
                    .font(.caption)
                    .foregroundStyle(.tertiary)

                Spacer()

                Button {
                    showThanks = true
                } label: {
                    Text(language.t("settings.feedbackSubmit"))
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.borderedProminent)
                .disabled(report.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(16)
            .navigationTitle(language.t("settings.feedback"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(language.t("common.cancel")) { dismiss() }
                }
            }
            .alert(language.t("settings.feedbackThanks"), isPresented: $showThanks) {
                Button(language.t("common.done")) { dismiss() }
            } message: {
                Text(language.t("settings.feedbackStub"))
            }
        }
        .presentationDetents([.medium, .large])
    }
}
