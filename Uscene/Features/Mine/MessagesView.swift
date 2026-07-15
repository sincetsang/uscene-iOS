import SwiftUI

struct MessagesView: View {
    @Environment(LanguageManager.self) private var language
    @Environment(AuthStore.self) private var auth

    @State private var messages: [InboxMessage] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showLogin = false

    var body: some View {
        Group {
            if !auth.isLoggedIn {
                ContentUnavailableView {
                    Label(language.t("login.pleaseLogin"), systemImage: "bell")
                } actions: {
                    Button(language.t("login.signIn")) { showLogin = true }
                }
            } else if isLoading && messages.isEmpty {
                ProgressView(language.t("common.loading"))
            } else if let errorMessage, messages.isEmpty {
                ContentUnavailableView {
                    Label(language.t("common.error"), systemImage: "exclamationmark.triangle")
                } description: {
                    Text(errorMessage)
                } actions: {
                    Button(language.t("common.retry")) { Task { await load() } }
                }
            } else if messages.isEmpty {
                ContentUnavailableView(language.t("messages.empty"), systemImage: "bell.slash")
            } else {
                List(messages) { message in
                    NavigationLink {
                        if let checkinId = message.checkin?.id {
                            CheckinDetailView(checkinId: checkinId)
                        }
                    } label: {
                        MessageRow(message: message)
                    }
                    .disabled(message.checkin?.id == nil)
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle(language.t("messages.title"))
        .sheet(isPresented: $showLogin) {
            NavigationStack { LoginView() }
        }
        .task { await load() }
        .refreshable { await load() }
    }

    @MainActor
    private func load() async {
        guard auth.isLoggedIn else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let response = try await MessageAPI.list()
            messages = response.messages ?? []
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct MessageRow: View {
    let message: InboxMessage

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            AsyncImage(url: URL(string: message.user?.avatar_url ?? "")) { phase in
                switch phase {
                case .success(let image): image.resizable().scaledToFill()
                default: Image("DefaultAvatar").resizable()
                }
            }
            .frame(width: 44, height: 44)
            .clipShape(Circle())

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(message.user?.nickname ?? "User")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    if let timestamp = message.timestamp {
                        Text(timestamp)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
                Text(message.content ?? "")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                if let checkin = message.checkin?.content, !checkin.isEmpty {
                    Text(checkin)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
        }
        .padding(.vertical, 4)
    }
}
