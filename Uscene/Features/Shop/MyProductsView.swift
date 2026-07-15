import SwiftUI

struct MyProductsView: View {
    @Environment(LanguageManager.self) private var language
    @Environment(AuthStore.self) private var auth

    /// 0 = selling (published), 1 = unpublished
    @State private var unpublished = 0
    @State private var rows: [UserProductSpotRow] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showLogin = false
    @State private var selectedProductId: Int?
    @State private var editProductId: Int?

    var body: some View {
        Group {
            if !auth.isLoggedIn {
                ContentUnavailableView {
                    Label(language.t("login.pleaseLogin"), systemImage: "bag")
                } actions: {
                    Button(language.t("login.signIn")) { showLogin = true }
                }
            } else if isLoading && rows.isEmpty {
                ProgressView(language.t("common.loading"))
            } else if let errorMessage, rows.isEmpty {
                ContentUnavailableView(language.t("common.error"), systemImage: "exclamationmark.triangle", description: Text(errorMessage))
            } else if rows.isEmpty {
                ContentUnavailableView(language.t("product.myEmpty"), systemImage: "bag")
            } else {
                List {
                    ForEach(rows) { row in
                        Section {
                            ForEach(row.products ?? []) { product in
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
                                        .frame(width: 64, height: 64)
                                        .clipShape(RoundedRectangle(cornerRadius: 8))

                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(product.name ?? "Product")
                                                .font(.headline)
                                                .foregroundStyle(.primary)
                                                .lineLimit(2)
                                            Text(product.displayPrice)
                                                .font(.subheadline.weight(.semibold))
                                                .foregroundStyle(Color.accentColor)
                                            HStack {
                                                if let visited = product.visited_count {
                                                    Text("\(visited) \(language.t("product.views"))")
                                                        .font(.caption)
                                                        .foregroundStyle(.secondary)
                                                }
                                                if let audit = product.audit_status, audit != 1 {
                                                    Text(audit == 2 ? language.t("product.rejected") : language.t("product.inReview"))
                                                        .font(.caption)
                                                        .foregroundStyle(.orange)
                                                }
                                            }
                                        }
                                        Spacer()
                                        Image(systemName: "chevron.right")
                                            .font(.caption)
                                            .foregroundStyle(.tertiary)
                                    }
                                }
                                .buttonStyle(.plain)
                                .swipeActions(edge: .trailing) {
                                    if unpublished == 1 {
                                        Button(language.t("product.publish")) {
                                            Task { await setPublished(product.id, publish: true) }
                                        }
                                        .tint(.green)
                                    } else {
                                        Button(language.t("product.unpublish")) {
                                            Task { await setPublished(product.id, publish: false) }
                                        }
                                        .tint(.orange)
                                    }
                                    Button {
                                        editProductId = product.id
                                    } label: {
                                        Label(language.t("product.edit"), systemImage: "pencil")
                                    }
                                    .tint(.blue)
                                }
                            }
                        } header: {
                            Text(row.title ?? language.t("landmark.detail"))
                        }
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
        .navigationTitle(language.t("product.myList"))
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink {
                    CreateProductView()
                } label: {
                    Image(systemName: "plus")
                }
                .disabled(!auth.isLoggedIn)
            }
        }
        .safeAreaInset(edge: .top) {
            Picker("", selection: $unpublished) {
                Text(language.t("product.selling")).tag(0)
                Text(language.t("product.unsold")).tag(1)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.bottom, 8)
            .background(.bar)
        }
        .onChange(of: unpublished) { _, _ in Task { await load() } }
        .sheet(isPresented: $showLogin) { NavigationStack { LoginView() } }
        .navigationDestination(isPresented: Binding(
            get: { selectedProductId != nil },
            set: { if !$0 { selectedProductId = nil } }
        )) {
            if let selectedProductId {
                ProductDetailView(productId: selectedProductId)
            }
        }
        .navigationDestination(item: $editProductId) { id in
            CreateProductView(editingProductId: id)
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
            let unpublishedParam = unpublished == 0 ? "" : "1"
            let response = try await CommerceAPI.myProducts(unpublished: unpublishedParam)
            rows = response.spotRows
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func setPublished(_ productId: Int, publish: Bool) async {
        do {
            if publish {
                try await CommerceAPI.publishProduct(productId: productId)
            } else {
                try await CommerceAPI.unpublishProduct(productId: productId)
            }
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
