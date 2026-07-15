import SwiftUI

struct ProductFavoritesView: View {
    @Environment(LanguageManager.self) private var language
    @Environment(AuthStore.self) private var auth

    @State private var products: [ShopProduct] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showLogin = false
    @State private var selectedProductId: Int?

    var body: some View {
        ProductBrowseList(
            title: language.t("product.favorites"),
            emptyText: language.t("product.favoritesEmpty"),
            emptyIcon: "heart.slash",
            products: products,
            isLoading: isLoading,
            errorMessage: errorMessage,
            needLogin: !auth.isLoggedIn,
            selectedProductId: $selectedProductId,
            onLogin: { showLogin = true },
            onRetry: { Task { await load() } }
        )
        .sheet(isPresented: $showLogin) { NavigationStack { LoginView() } }
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
            products = try await CommerceAPI.productFavorites().flatProducts
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct ProductHistoryView: View {
    @Environment(LanguageManager.self) private var language
    @Environment(AuthStore.self) private var auth

    @State private var products: [ShopProduct] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showLogin = false
    @State private var selectedProductId: Int?

    var body: some View {
        ProductBrowseList(
            title: language.t("product.history"),
            emptyText: language.t("product.historyEmpty"),
            emptyIcon: "clock",
            products: products,
            isLoading: isLoading,
            errorMessage: errorMessage,
            needLogin: !auth.isLoggedIn,
            selectedProductId: $selectedProductId,
            onLogin: { showLogin = true },
            onRetry: { Task { await load() } }
        )
        .sheet(isPresented: $showLogin) { NavigationStack { LoginView() } }
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
            products = try await CommerceAPI.productVisitHistory().flatProducts
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct ProductBrowseList: View {
    @Environment(LanguageManager.self) private var language

    let title: String
    let emptyText: String
    let emptyIcon: String
    let products: [ShopProduct]
    let isLoading: Bool
    let errorMessage: String?
    let needLogin: Bool
    @Binding var selectedProductId: Int?
    let onLogin: () -> Void
    let onRetry: () -> Void

    var body: some View {
        Group {
            if needLogin {
                ContentUnavailableView {
                    Label(language.t("login.pleaseLogin"), systemImage: "bag")
                } actions: {
                    Button(language.t("login.signIn"), action: onLogin)
                }
            } else if isLoading && products.isEmpty {
                ProgressView(language.t("common.loading"))
            } else if let errorMessage, products.isEmpty {
                ContentUnavailableView(language.t("common.error"), systemImage: "exclamationmark.triangle", description: Text(errorMessage))
            } else if products.isEmpty {
                ContentUnavailableView(emptyText, systemImage: emptyIcon)
            } else {
                List(products) { product in
                    Button {
                        selectedProductId = product.id
                    } label: {
                        HStack(spacing: 12) {
                            AsyncImage(url: URL(string: product.cover ?? "")) { phase in
                                switch phase {
                                case .success(let image): image.resizable().scaledToFill()
                                default: Color.gray.opacity(0.12)
                                }
                            }
                            .frame(width: 56, height: 56)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            VStack(alignment: .leading, spacing: 4) {
                                Text(product.name ?? "Product").font(.headline).lineLimit(2).foregroundStyle(.primary)
                                Text(product.displayPrice)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(Color.accentColor)
                            }
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle(title)
        .navigationDestination(isPresented: Binding(
            get: { selectedProductId != nil },
            set: { if !$0 { selectedProductId = nil } }
        )) {
            if let selectedProductId {
                ProductDetailView(productId: selectedProductId)
            }
        }
        .toolbar {
            if errorMessage != nil, !products.isEmpty {
                ToolbarItem(placement: .bottomBar) {
                    Button(language.t("common.retry"), action: onRetry)
                }
            }
        }
    }
}
