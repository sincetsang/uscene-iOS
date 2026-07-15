import SwiftUI
import UIKit

struct ProductDetailView: View {
    @Environment(LanguageManager.self) private var language
    @Environment(AuthStore.self) private var auth

    let productId: Int

    @State private var detail: ProductDetail?
    @State private var comments: [ProductComment] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showLogin = false
    @State private var checkoutProduct: ProductDetail?
    @State private var contactCopied = false
    @State private var previewIndex: Int?

    private var isCodePackage: Bool { (detail?.check_code_num ?? 0) > 0 }

    private var isOwner: Bool {
        guard let ownerId = detail?.owner_id else { return false }
        return (auth.user?.user_id ?? auth.user?.id) == ownerId
    }

    var body: some View {
        content
            .navigationTitle(language.t("shop.detail"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ownerToolbar }
            .fullScreenCover(item: previewBinding) { item in
                ProductImagePreview(urlString: item.url) { previewIndex = nil }
            }
            .sheet(isPresented: $showLogin) { NavigationStack { LoginView() } }
            .navigationDestination(item: $checkoutProduct) { product in
                if (product.check_code_num ?? 0) > 0 {
                    CreateCodeOrderView(product: product)
                } else {
                    CreateProductOrderView(product: product)
                }
            }
            .task { await load() }
    }

    @ViewBuilder
    private var content: some View {
        if isLoading && detail == nil {
            ProgressView(language.t("common.loading"))
        } else if let errorMessage, detail == nil {
            ContentUnavailableView {
                Label(language.t("common.error"), systemImage: "exclamationmark.triangle")
            } description: {
                Text(errorMessage)
            } actions: {
                Button(language.t("common.retry")) { Task { await load() } }
            }
        } else if let detail {
            detailScroll(detail)
        }
    }

    private func detailScroll(_ detail: ProductDetail) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                gallery(detail)
                infoBlock(detail)
                commentsBlock
            }
            .padding(.bottom, 90)
        }
        .safeAreaInset(edge: .bottom) { bottomBar(detail) }
    }

    private func gallery(_ detail: ProductDetail) -> some View {
        let urls = detail.gallery
        return TabView {
            ForEach(Array(urls.enumerated()), id: \.offset) { index, url in
                Button { previewIndex = index } label: {
                    AsyncImage(url: URL(string: url)) { phase in
                        switch phase {
                        case .success(let image): image.resizable().scaledToFill()
                        default: Color.gray.opacity(0.12)
                        }
                    }
                    .frame(height: 260)
                    .frame(maxWidth: .infinity)
                    .clipped()
                }
                .buttonStyle(.plain)
            }
        }
        .frame(height: 260)
        .tabViewStyle(.page(indexDisplayMode: urls.count > 1 ? .automatic : .never))
    }

    private func infoBlock(_ detail: ProductDetail) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(detail.name ?? "Product").font(.title2.bold())
            Text(detail.displayPrice)
                .font(.title3.weight(.semibold))
                .foregroundStyle(Theme.brand)

            if let tags = detail.tags, !tags.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(tags) { tag in
                            Text(tag.displayName)
                                .font(.caption)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Theme.chipFill, in: Capsule())
                        }
                    }
                }
            }

            if let desc = detail.description, !desc.isEmpty {
                Text(desc).font(.body)
            }

            HStack(spacing: 16) {
                Label("\(detail.favorite_count ?? 0)", systemImage: detail.is_favorite == true ? "heart.fill" : "heart")
                Label("\(detail.comment_count ?? 0)", systemImage: "bubble.right")
                Label("\(detail.visited_count ?? 0)", systemImage: "eye")
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            if let spotId = detail.spot_id, spotId > 0 {
                NavigationLink {
                    LandmarkDetailView(spotId: spotId)
                } label: {
                    Label(
                        detail.spot_title_cn ?? detail.spot_title_en ?? language.t("landmark.detail"),
                        systemImage: "mappin"
                    )
                    .font(.subheadline)
                }
            } else if let spot = detail.spot_title_cn ?? detail.spot_title_en {
                Label(spot, systemImage: "mappin")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal)
    }

    @ViewBuilder
    private var commentsBlock: some View {
        if !comments.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text(language.t("shop.comments")).font(.headline).padding(.horizontal)
                ForEach(comments) { comment in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(comment.user?.nickname ?? "User").font(.subheadline.weight(.semibold))
                            Spacer()
                            if let star = comment.star {
                                Text(String(repeating: "★", count: max(0, min(5, star))))
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                            }
                        }
                        Text(comment.content ?? "").font(.subheadline).foregroundStyle(.secondary)
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 6)
                }
            }
        }
    }

    private func bottomBar(_ detail: ProductDetail) -> some View {
        HStack(spacing: 12) {
            Button { Task { await toggleFavorite() } } label: {
                Image(systemName: detail.is_favorite == true ? "heart.fill" : "heart")
                    .frame(width: 48, height: 48)
                    .background(Color(.secondarySystemBackground), in: Circle())
            }

            if let wechat = detail.wechat, !wechat.isEmpty, !isOwner {
                Button {
                    UIPasteboard.general.string = wechat
                    contactCopied = true
                } label: {
                    Image(systemName: "message.fill")
                        .frame(width: 48, height: 48)
                        .background(Color(.secondarySystemBackground), in: Circle())
                }
                .accessibilityLabel(language.t("product.contactSeller"))
            }

            Button {
                if auth.isLoggedIn {
                    checkoutProduct = detail
                } else {
                    showLogin = true
                }
            } label: {
                Text(isCodePackage ? language.t("shop.buyCodes") : language.t("shop.buy"))
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Theme.brand)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
        .padding()
        .background(.bar)
        .overlay(alignment: .top) {
            if contactCopied {
                Text(language.t("product.wechatCopied"))
                    .font(.caption)
                    .padding(6)
                    .background(.ultraThinMaterial, in: Capsule())
                    .offset(y: -28)
                    .task {
                        try? await Task.sleep(nanoseconds: 1_500_000_000)
                        contactCopied = false
                    }
            }
        }
    }

    @ToolbarContentBuilder
    private var ownerToolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            if isOwner, let detail {
                Menu {
                    NavigationLink {
                        CreateProductView(spotId: detail.spot_id, editingProductId: productId)
                    } label: {
                        Label(language.t("product.edit"), systemImage: "pencil")
                    }
                    if detail.is_active == true {
                        Button { Task { await setPublished(false) } } label: {
                            Label(language.t("product.unpublish"), systemImage: "eye.slash")
                        }
                    } else {
                        Button { Task { await setPublished(true) } } label: {
                            Label(language.t("product.publish"), systemImage: "eye")
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
    }

    private var previewBinding: Binding<ProductPreviewItem?> {
        Binding(
            get: {
                guard let previewIndex, let urls = detail?.gallery, urls.indices.contains(previewIndex) else { return nil }
                return ProductPreviewItem(id: previewIndex, url: urls[previewIndex])
            },
            set: { previewIndex = $0?.id }
        )
    }

    @MainActor
    private func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let uid = auth.user?.user_id ?? auth.user?.id
            detail = try await CommerceAPI.productDetail(productId: productId, isOwner: 0)
            if let ownerId = detail?.owner_id, ownerId == uid {
                detail = try await CommerceAPI.productDetail(productId: productId, isOwner: 1)
            }
            comments = (try? await CommerceAPI.productComments(productId: productId)) ?? []
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func toggleFavorite() async {
        guard auth.isLoggedIn else {
            showLogin = true
            return
        }
        guard let detail else { return }
        do {
            if detail.is_favorite == true {
                try await CommerceAPI.favoriteDelete(productId: productId)
            } else {
                try await CommerceAPI.favoriteAdd(productId: productId)
            }
            self.detail = try await CommerceAPI.productDetail(productId: productId, isOwner: isOwner ? 1 : 0)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func setPublished(_ publish: Bool) async {
        do {
            if publish {
                try await CommerceAPI.publishProduct(productId: productId)
            } else {
                try await CommerceAPI.unpublishProduct(productId: productId)
            }
            detail = try await CommerceAPI.productDetail(productId: productId, isOwner: 1)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct ProductPreviewItem: Identifiable {
    let id: Int
    let url: String
}

private struct ProductImagePreview: View {
    let urlString: String
    let onClose: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()
            AsyncImage(url: URL(string: urlString)) { phase in
                switch phase {
                case .success(let image): image.resizable().scaledToFit()
                default: ProgressView().tint(.white)
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
