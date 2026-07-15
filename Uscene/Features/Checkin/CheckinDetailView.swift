import SwiftUI

struct CheckinDetailView: View {
    @Environment(LanguageManager.self) private var language
    @Environment(AuthStore.self) private var auth
    @Environment(\.dismiss) private var dismiss

    let checkinId: Int

    @State private var payload: CheckinDetailPayload?
    @State private var threads: [CheckinCommentThread] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var commentText = ""
    @State private var replyTo: CheckinComment?
    @State private var isActing = false
    @State private var showLogin = false
    @State private var isPrivate = false
    @State private var isFollowing = false
    @State private var previewURL: String?
    @State private var confirmDelete = false

    private var isCheckinOwner: Bool {
        let uid = auth.user?.user_id ?? auth.user?.id
        let author = payload?.checkin?.user_id
            ?? payload?.checkin?.user?.user_id
            ?? payload?.checkin?.user?.id
            ?? payload?.user?.user_id
            ?? payload?.user?.id
        return uid != nil && uid == author
    }

    private var authorUserId: Int? {
        payload?.checkin?.user?.user_id
            ?? payload?.checkin?.user?.id
            ?? payload?.user?.user_id
            ?? payload?.user?.id
            ?? payload?.checkin?.user_id
    }

    var body: some View {
        Group {
            if isLoading && payload == nil {
                ProgressView(language.t("common.loading"))
            } else if let errorMessage, payload == nil {
                ContentUnavailableView {
                    Label(language.t("common.error"), systemImage: "exclamationmark.triangle")
                } description: {
                    Text(errorMessage)
                } actions: {
                    Button(language.t("common.retry")) { Task { await load() } }
                }
            } else if let checkin = payload?.checkin {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        header(checkin)
                        if let point = payload?.point {
                            NavigationLink {
                                LandmarkDetailView(spotId: point.resolvedId)
                            } label: {
                                HStack {
                                    Label(point.displayTitle, systemImage: "mappin.circle")
                                    Spacer()
                                    if let distance = payload?.distance {
                                        Text(formatMeters(distance))
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            }
                        }
                        Text(checkin.content ?? "")
                            .font(.body)
                        imagesGrid(checkin)
                        actionRow(checkin)

                        Text(language.t("checkin.comments"))
                            .font(.headline)

                        if threads.isEmpty {
                            Text(language.t("checkin.noComments"))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(threads) { thread in
                                if let comment = thread.comment {
                                    commentBlock(comment, isReply: false)
                                    ForEach(thread.replies ?? []) { reply in
                                        commentBlock(reply, isReply: true)
                                    }
                                }
                            }
                        }

                        if auth.isLoggedIn {
                            VStack(alignment: .leading, spacing: 8) {
                                if let replyTo {
                                    HStack {
                                        Text("\(language.t("checkin.replying")) \(replyTo.user?.nickname ?? "")")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                        Spacer()
                                        Button(language.t("common.cancel")) { self.replyTo = nil }
                                            .font(.caption)
                                    }
                                }
                                HStack {
                                    TextField(
                                        replyTo == nil
                                            ? language.t("checkin.commentPlaceholder")
                                            : language.t("checkin.replyPlaceholder"),
                                        text: $commentText
                                    )
                                    .textFieldStyle(.roundedBorder)
                                    Button(language.t("checkin.sendComment")) {
                                        Task { await sendComment() }
                                    }
                                    .disabled(isActing || commentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                                }
                            }
                        } else {
                            Button(language.t("login.pleaseLogin")) { showLogin = true }
                                .font(.subheadline)
                        }

                        if let errorMessage {
                            Text(errorMessage).font(.caption).foregroundStyle(.red)
                        }
                    }
                    .padding()
                }
            }
        }
        .navigationTitle(language.t("checkin.detail"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if isCheckinOwner {
                    Menu {
                        Button {
                            Task { await togglePrivate() }
                        } label: {
                            Label(
                                isPrivate ? language.t("checkin.makePublic") : language.t("checkin.private"),
                                systemImage: isPrivate ? "eye" : "eye.slash"
                            )
                        }
                        Button(role: .destructive) {
                            confirmDelete = true
                        } label: {
                            Label(language.t("common.delete"), systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
        }
        .confirmationDialog(language.t("checkin.deleteConfirm"), isPresented: $confirmDelete, titleVisibility: .visible) {
            Button(language.t("common.delete"), role: .destructive) {
                Task { await deleteCheckin() }
            }
            Button(language.t("common.cancel"), role: .cancel) {}
        }
        .fullScreenCover(item: Binding(
            get: { previewURL.map { PreviewItem(url: $0) } },
            set: { previewURL = $0?.url }
        )) { item in
            ImagePreviewView(urlString: item.url) {
                previewURL = nil
            }
        }
        .sheet(isPresented: $showLogin) {
            NavigationStack { LoginView() }
        }
        .task { await load() }
    }

    @ViewBuilder
    private func header(_ checkin: Checkin) -> some View {
        HStack(spacing: 12) {
            if let userId = authorUserId {
                NavigationLink {
                    UserHomeView(userId: userId)
                } label: {
                    userRow(checkin)
                }
                .buttonStyle(.plain)
            } else {
                userRow(checkin)
            }
            Spacer()
            if auth.isLoggedIn, let userId = authorUserId, !isCheckinOwner {
                Button {
                    Task { await toggleFollow(userId: userId) }
                } label: {
                    Text(isFollowing ? language.t("user.unfollow") : language.t("user.follow"))
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(isFollowing ? Color.gray.opacity(0.15) : Theme.brand)
                        .foregroundStyle(isFollowing ? Theme.text : .white)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .disabled(isActing)
            }
            if isPrivate {
                Image(systemName: "lock.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func userRow(_ checkin: Checkin) -> some View {
        HStack(spacing: 12) {
            AsyncImage(url: URL(string: checkin.user?.avatar_url ?? payload?.user?.avatar_url ?? "")) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFill()
                default:
                    Image("DefaultAvatar").resizable().scaledToFill()
                }
            }
            .frame(width: 44, height: 44)
            .clipShape(Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(checkin.user?.nickname ?? payload?.user?.nickname ?? "User")
                    .font(.headline)
                if let created = checkin.created_at {
                    Text(created)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private func imagesGrid(_ checkin: Checkin) -> some View {
        if let images = checkin.images, !images.isEmpty {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                ForEach(images, id: \.image_url) { image in
                    Button {
                        previewURL = image.image_url
                    } label: {
                        AsyncImage(url: URL(string: image.image_url ?? "")) { phase in
                            switch phase {
                            case .success(let img):
                                img.resizable().scaledToFill()
                            default:
                                Color.gray.opacity(0.1)
                            }
                        }
                        .frame(minHeight: 140)
                        .clipped()
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func actionRow(_ checkin: Checkin) -> some View {
        HStack(spacing: 16) {
            Button {
                Task { await toggleLike() }
            } label: {
                Label(
                    "\(checkin.like_count ?? 0)",
                    systemImage: (payload?.is_liked ?? checkin.is_liked) == true ? "heart.fill" : "heart"
                )
            }
            .disabled(isActing)

            Label("\(checkin.comment_count ?? threads.count)", systemImage: "bubble.right")
        }
        .font(.subheadline)
        .foregroundStyle(.secondary)
    }

    private func commentBlock(_ comment: CheckinComment, isReply: Bool) -> some View {
        HStack(alignment: .top, spacing: 10) {
            if isReply {
                Color.clear.frame(width: 28)
            }
            AsyncImage(url: URL(string: comment.user?.avatar_url ?? "")) { phase in
                switch phase {
                case .success(let image): image.resizable().scaledToFill()
                default: Image("DefaultAvatar").resizable().scaledToFill()
                }
            }
            .frame(width: isReply ? 28 : 32, height: isReply ? 28 : 32)
            .clipShape(Circle())

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(comment.user?.nickname ?? "User")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Button {
                        Task { await toggleCommentLike(comment) }
                    } label: {
                        Label(
                            "\(comment.like_count ?? 0)",
                            systemImage: comment.is_liked == true ? "heart.fill" : "heart"
                        )
                        .font(.caption)
                    }
                    .buttonStyle(.borderless)
                    .disabled(isActing)
                }
                Text(comment.content ?? "")
                    .font(.subheadline)
                HStack(spacing: 12) {
                    if let created = comment.created_at {
                        Text(created).font(.caption2).foregroundStyle(.secondary)
                    }
                    if auth.isLoggedIn {
                        Button(language.t("checkin.reply")) {
                            replyTo = comment
                        }
                        .font(.caption)
                    }
                    if isOwner(of: comment) {
                        Button(role: .destructive) {
                            Task { await deleteComment(comment) }
                        } label: {
                            Text(language.t("common.delete"))
                        }
                        .font(.caption)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func isOwner(of comment: CheckinComment) -> Bool {
        let uid = auth.user?.user_id ?? auth.user?.id
        let commentUid = comment.user?.user_id ?? comment.user?.id
        return uid != nil && uid == commentUid
    }

    private func formatMeters(_ meters: Double) -> String {
        if meters < 1000 { return String(format: "%.0fm", meters) }
        return String(format: "%.1fkm", meters / 1000)
    }

    @MainActor
    private func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let detail = try await CheckinAPI.detail(checkinId: checkinId)
            payload = detail
            isPrivate = detail.checkin?.private == true
            threads = (try? await CheckinAPI.commentList(checkinId: checkinId)) ?? []
            if let userId = authorUserId, !isCheckinOwner {
                let other = try? await UserAPI.otherInfo(userId: userId)
                isFollowing = other?.is_followed == true
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func togglePrivate() async {
        isActing = true
        defer { isActing = false }
        do {
            let next = !isPrivate
            try await CheckinAPI.updatePrivate(checkinId: checkinId, isPrivate: next)
            isPrivate = next
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func deleteCheckin() async {
        isActing = true
        defer { isActing = false }
        do {
            try await CheckinAPI.delete(checkinId: checkinId)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func toggleFollow(userId: Int) async {
        guard auth.isLoggedIn else {
            showLogin = true
            return
        }
        isActing = true
        defer { isActing = false }
        do {
            let result = try await UserAPI.follow(userId: userId)
            isFollowing = result.is_followed == true
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func toggleLike() async {
        guard auth.isLoggedIn else {
            showLogin = true
            return
        }
        isActing = true
        defer { isActing = false }
        do {
            try await CheckinAPI.like(checkinId: checkinId)
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func sendComment() async {
        let text = commentText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        isActing = true
        defer { isActing = false }
        do {
            if let replyTo {
                try await CheckinAPI.replyComment(checkinId: checkinId, commentId: replyTo.id, content: text)
                self.replyTo = nil
            } else {
                try await CheckinAPI.addComment(checkinId: checkinId, content: text)
            }
            commentText = ""
            threads = (try? await CheckinAPI.commentList(checkinId: checkinId)) ?? []
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func toggleCommentLike(_ comment: CheckinComment) async {
        guard auth.isLoggedIn else {
            showLogin = true
            return
        }
        isActing = true
        defer { isActing = false }
        do {
            try await CheckinAPI.likeComment(checkinId: checkinId, commentId: comment.id)
            threads = (try? await CheckinAPI.commentList(checkinId: checkinId)) ?? []
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func deleteComment(_ comment: CheckinComment) async {
        isActing = true
        defer { isActing = false }
        do {
            try await CheckinAPI.deleteComment(checkinId: checkinId, commentId: comment.id)
            threads = (try? await CheckinAPI.commentList(checkinId: checkinId)) ?? []
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct PreviewItem: Identifiable {
    let url: String
    var id: String { url }
}

private struct ImagePreviewView: View {
    let urlString: String
    let onClose: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()
            AsyncImage(url: URL(string: urlString)) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFit()
                default:
                    ProgressView().tint(.white)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Button(action: onClose) {
                Image(systemName: "xmark.circle.fill")
                    .font(.title)
                    .foregroundStyle(.white.opacity(0.9))
                    .padding()
            }
        }
    }
}
