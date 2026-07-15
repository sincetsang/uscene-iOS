import SwiftUI

struct UserHomeView: View {
    @Environment(LanguageManager.self) private var language
    @Environment(AuthStore.self) private var auth

    let userId: Int

    @State private var profile: OtherUserPayload?
    @State private var checkins: [CheckinFeedItem] = []
    @State private var isLoading = false
    @State private var isFollowing = false
    @State private var isFollowed = false
    @State private var errorMessage: String?
    @State private var showLogin = false
    @State private var selectedCheckinId: Int?

    var body: some View {
        Group {
            if isLoading && profile == nil {
                ProgressView(language.t("common.loading"))
            } else if let errorMessage, profile == nil {
                ContentUnavailableView(language.t("common.error"), systemImage: "exclamationmark.triangle", description: Text(errorMessage))
            } else if let profile {
                List {
                    Section {
                        HStack(spacing: 14) {
                            AsyncImage(url: URL(string: profile.user?.avatar_url ?? "")) { phase in
                                switch phase {
                                case .success(let image): image.resizable().scaledToFill()
                                default: Image("DefaultAvatar").resizable().scaledToFill()
                                }
                            }
                            .frame(width: 72, height: 72)
                            .clipShape(Circle())

                            VStack(alignment: .leading, spacing: 6) {
                                Text(profile.user?.nickname ?? "User")
                                    .font(.title3.bold())
                                if let desc = profile.user?.profileDescription, !desc.isEmpty {
                                    Text(desc)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(3)
                                }
                                HStack(spacing: 12) {
                                    Label("\(profile.checkin_count ?? checkins.count)", systemImage: "checkmark.circle")
                                    if let followers = profile.follower_count {
                                        Label("\(followers)", systemImage: "person.2")
                                    }
                                }
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                        .padding(.vertical, 4)

                        if !isSelf {
                            Button {
                                Task { await toggleFollow() }
                            } label: {
                                Text(isFollowed ? language.t("user.unfollow") : language.t("user.follow"))
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(isFollowing)
                        }
                    }

                    Section(language.t("user.checkins")) {
                        if checkins.isEmpty {
                            Text(language.t("checkin.feedEmpty"))
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(checkins) { item in
                                Button {
                                    selectedCheckinId = item.checkin?.id
                                } label: {
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text(item.checkin?.content ?? "")
                                            .font(.subheadline)
                                            .foregroundStyle(.primary)
                                            .lineLimit(3)
                                        if let title = item.point?.title {
                                            Label(title, systemImage: "mappin")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                    .padding(.vertical, 2)
                                }
                            }
                        }
                    }

                    if let errorMessage {
                        Section { Text(errorMessage).foregroundStyle(.red) }
                    }
                }
            }
        }
        .navigationTitle(language.t("user.profile"))
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showLogin) { NavigationStack { LoginView() } }
        .navigationDestination(isPresented: Binding(
            get: { selectedCheckinId != nil },
            set: { if !$0 { selectedCheckinId = nil } }
        )) {
            if let selectedCheckinId {
                CheckinDetailView(checkinId: selectedCheckinId)
            }
        }
        .task { await load() }
        .refreshable { await load() }
    }

    private var isSelf: Bool {
        let uid = auth.user?.user_id ?? auth.user?.id
        return uid == userId
    }

    @MainActor
    private func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            async let profileTask = UserAPI.otherInfo(userId: userId)
            async let checkinsTask = UserAPI.checkins(userId: userId)
            profile = try await profileTask
            checkins = (try? await checkinsTask) ?? []
            isFollowed = profile?.is_followed ?? false
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func toggleFollow() async {
        guard auth.isLoggedIn else {
            showLogin = true
            return
        }
        isFollowing = true
        defer { isFollowing = false }
        do {
            let result = try await UserAPI.follow(userId: userId)
            isFollowed = result.is_followed ?? !isFollowed
            profile = try? await UserAPI.otherInfo(userId: userId)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
