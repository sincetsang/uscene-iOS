import SwiftUI

struct CheckinFeedView: View {
    enum SpotSort: String, CaseIterable, Identifiable {
        case latest
        case recommended
        var id: String { rawValue }
    }

    @Environment(LanguageManager.self) private var language
    @Environment(LocationManager.self) private var location

    var spotId: Int? = nil
    var topicId: Int = 0

    @State private var sort: SpotSort = .latest
    @State private var items: [CheckinFeedItem] = []
    @State private var isLoading = false
    @State private var isLoadingMore = false
    @State private var page = 1
    @State private var canLoadMore = true
    @State private var errorMessage: String?
    @State private var topics: [CheckinTag] = []
    @State private var selectedTopicId = 0

    var body: some View {
        VStack(spacing: 0) {
            feedFilterBar
                .padding(.vertical, 8)
                .background(Color(.systemBackground))

            Divider().opacity(0.3)

            Group {
                if isLoading && items.isEmpty {
                    ProgressView(language.t("common.loading"))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let errorMessage, items.isEmpty {
                    ContentUnavailableView(language.t("common.error"), systemImage: "exclamationmark.triangle", description: Text(errorMessage))
                } else if items.isEmpty {
                    ContentUnavailableView(language.t("checkin.feedEmpty"), systemImage: "text.bubble")
                } else {
                    List {
                        ForEach(items) { item in
                            if let id = item.checkin?.id {
                                NavigationLink {
                                    CheckinDetailView(checkinId: id)
                                } label: {
                                    CheckinFeedRow(item: item)
                                }
                            } else {
                                CheckinFeedRow(item: item)
                            }
                        }
                        if canLoadMore {
                            HStack {
                                Spacer()
                                if isLoadingMore {
                                    ProgressView()
                                } else {
                                    Text(language.t("common.loadMore"))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                            }
                            .onAppear {
                                Task { await loadMore() }
                            }
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationTitle(language.t("checkin.feed"))
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if spotId == nil {
                topics = (try? await CheckinAPI.tags()) ?? []
                selectedTopicId = topicId
            }
            await reload()
        }
        .refreshable { await reload() }
    }

    @ViewBuilder
    private var feedFilterBar: some View {
        if spotId != nil {
            Picker("", selection: $sort) {
                Text(language.t("checkin.latest")).tag(SpotSort.latest)
                Text(language.t("checkin.recommended")).tag(SpotSort.recommended)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .onChange(of: sort) { _, _ in
                Task { await reload() }
            }
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    topicChip(id: 0, title: language.t("checkin.topicAll"))
                    ForEach(topics) { tag in
                        if let intId = Int(tag.resolvedId) {
                            topicChip(id: intId, title: tag.displayName)
                        }
                    }
                }
                .padding(.horizontal)
            }
            // Keep a stable height so the bar doesn't pop in after topics load.
            .frame(height: 36)
        }
    }

    private func topicChip(id: Int, title: String) -> some View {
        Button {
            selectedTopicId = id
            Task { await reload() }
        } label: {
            Text(title)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(selectedTopicId == id ? Color.accentColor.opacity(0.15) : Color.gray.opacity(0.12))
                .foregroundStyle(selectedTopicId == id ? Color.accentColor : .secondary)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    @MainActor
    private func reload() async {
        page = 1
        canLoadMore = true
        await load(page: 1, append: false)
    }

    @MainActor
    private func loadMore() async {
        guard canLoadMore, !isLoading, !isLoadingMore else { return }
        await load(page: page + 1, append: true)
    }

    @MainActor
    private func load(page pageToLoad: Int, append: Bool) async {
        if append {
            isLoadingMore = true
        } else {
            isLoading = true
        }
        errorMessage = nil
        defer {
            isLoading = false
            isLoadingMore = false
        }
        do {
            let fetched: [CheckinFeedItem]
            if let spotId {
                switch sort {
                case .latest:
                    fetched = try await CheckinAPI.spotLatest(spotId: spotId, page: pageToLoad)
                case .recommended:
                    fetched = try await CheckinAPI.spotRecommended(spotId: spotId, page: pageToLoad)
                }
            } else {
                let lat = location.coordinate?.latitude ?? 22.2987
                let lng = location.coordinate?.longitude ?? 114.1723
                fetched = try await CheckinAPI.feed(
                    latitude: lat,
                    longitude: lng,
                    page: pageToLoad,
                    topicId: selectedTopicId
                )
            }
            if append {
                let existing = Set(items.map(\.id))
                items.append(contentsOf: fetched.filter { !existing.contains($0.id) })
            } else {
                items = fetched
            }
            page = pageToLoad
            canLoadMore = fetched.count >= 20
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct CheckinFeedRow: View {
    let item: CheckinFeedItem

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            AsyncImage(url: URL(string: item.user?.avatar_url ?? item.checkin?.user?.avatar_url ?? "")) { phase in
                switch phase {
                case .success(let image): image.resizable().scaledToFill()
                default: Image("DefaultAvatar").resizable()
                }
            }
            .frame(width: 44, height: 44)
            .clipShape(Circle())

            VStack(alignment: .leading, spacing: 6) {
                Text(item.user?.nickname ?? item.checkin?.user?.nickname ?? "User")
                    .font(.subheadline.weight(.semibold))
                Text(item.checkin?.content ?? "")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                if let title = item.point?.title {
                    Label(title, systemImage: "mappin")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                HStack(spacing: 12) {
                    Label("\(item.checkin?.like_count ?? 0)", systemImage: "heart")
                    Label("\(item.checkin?.comment_count ?? 0)", systemImage: "bubble.right")
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}
