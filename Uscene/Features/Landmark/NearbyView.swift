import SwiftUI

struct NearbyView: View {
    @Environment(LanguageManager.self) private var language

    let latitude: Double
    let longitude: Double

    @State private var items: [NearbySpotItem] = []
    @State private var categories: [CategoryItem] = []
    @State private var selectedCategory = ""
    @State private var page = 1
    @State private var totalCount = 0
    @State private var isLoading = false
    @State private var isLoadingMore = false
    @State private var errorMessage: String?

    private let pageSize = 20

    private var canLoadMore: Bool {
        !items.isEmpty && items.count < totalCount
    }

    var body: some View {
        VStack(spacing: 0) {
            categoryChips
                .padding(.vertical, 8)
                .background(Color(.systemBackground))

            Divider().opacity(0.3)

            Group {
                if isLoading && items.isEmpty {
                    ProgressView(language.t("common.loading"))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let errorMessage, items.isEmpty {
                    ContentUnavailableView {
                        Label(language.t("common.error"), systemImage: "exclamationmark.triangle")
                    } description: {
                        Text(errorMessage)
                    } actions: {
                        Button(language.t("common.retry")) { Task { await reload() } }
                    }
                } else if items.isEmpty {
                    ContentUnavailableView(language.t("map.empty"), systemImage: "mappin.slash")
                } else {
                    List {
                        ForEach(items) { item in
                            NavigationLink {
                                LandmarkDetailView(spotId: item.point.resolvedId)
                            } label: {
                                NearbyRow(item: item)
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
        }
        .navigationTitle(language.t("map.nearby"))
        .navigationBarTitleDisplayMode(.inline)
        .task {
            categories = (try? await SpotAPI.categories()) ?? []
            await reload()
        }
        .refreshable { await reload() }
    }

    private var categoryChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip(key: "", title: language.t("checkin.topicAll"))
                ForEach(categories) { category in
                    chip(key: category.categoryKey, title: category.displayName)
                }
            }
            .padding(.horizontal, 16)
        }
        .frame(height: 36)
    }

    private func chip(key: String, title: String) -> some View {
        Button {
            guard selectedCategory != key else { return }
            selectedCategory = key
            Task { await reload() }
        } label: {
            Text(title)
                .font(.system(size: 14))
                .foregroundStyle(selectedCategory == key ? Theme.brand : Theme.text)
                .padding(.horizontal, 14)
                .frame(height: 32)
                .background(Theme.chipFill, in: RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(selectedCategory == key ? Theme.brand : Color.clear, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    @MainActor
    private func reload() async {
        page = 1
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let result = try await SpotAPI.nearbyPage(
                latitude: latitude,
                longitude: longitude,
                category: selectedCategory,
                page: 1
            )
            items = result.items
            totalCount = result.total
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func loadMore() async {
        guard canLoadMore, !isLoading, !isLoadingMore else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        let next = page + 1
        do {
            let result = try await SpotAPI.nearbyPage(
                latitude: latitude,
                longitude: longitude,
                category: selectedCategory,
                page: next
            )
            let existing = Set(items.map(\.id))
            items.append(contentsOf: result.items.filter { !existing.contains($0.id) })
            totalCount = max(totalCount, result.total)
            page = next
            if result.items.count < pageSize {
                totalCount = items.count
            }
        } catch {
            // Keep existing rows; user can retry by scrolling again.
        }
    }
}

struct NearbyRow: View {
    let item: NearbySpotItem

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                AsyncImage(url: URL(string: item.displayImage ?? "")) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    default:
                        Color.gray.opacity(0.15)
                    }
                }
                .frame(width: 72, height: 72)
                .clipShape(RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 6) {
                    Text(item.displayTitle)
                        .font(.headline)
                        .lineLimit(1)

                    HStack(spacing: 8) {
                        if let category = item.category, !category.isEmpty {
                            Text(category)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Label("\(item.point.like_count ?? 0)", systemImage: "heart")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    HStack(spacing: 6) {
                        if let distance = item.distance {
                            Text(Theme.formatDistance(distance))
                                .font(.caption2)
                                .foregroundStyle(Theme.brand)
                        }
                        if let location = item.point.location, !location.isEmpty {
                            Text("·")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                            Text(location)
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                        }
                    }
                }
                Spacer(minLength: 0)
            }

            if let product = item.firstProduct {
                HStack(spacing: 8) {
                    AsyncImage(url: URL(string: product.cover ?? "")) { phase in
                        switch phase {
                        case .success(let image):
                            image.resizable().scaledToFill()
                        default:
                            Color.gray.opacity(0.1)
                        }
                    }
                    .frame(width: 28, height: 28)
                    .clipShape(RoundedRectangle(cornerRadius: 4))

                    Text(product.displayPrice)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.shop)
                    Text(product.name ?? "")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(Color(red: 0.969, green: 0.973, blue: 0.98), in: RoundedRectangle(cornerRadius: 8))
            }
        }
        .padding(.vertical, 4)
    }
}
