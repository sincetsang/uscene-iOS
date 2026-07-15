import SwiftUI

struct SpotSearchView: View {
    enum Tab: String, CaseIterable, Identifiable {
        case spots
        case products
        var id: String { rawValue }
    }

    @Environment(LanguageManager.self) private var language

    let latitude: Double
    let longitude: Double

    @State private var tab: Tab = .spots
    @State private var keyword = ""
    @State private var spots: [NearbySpotItem] = []
    @State private var products: [ShopProduct] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var searchTask: Task<Void, Never>?
    @State private var selectedProductId: Int?

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $tab) {
                Text(language.t("search.tabSpots")).tag(Tab.spots)
                Text(language.t("search.tabProducts")).tag(Tab.products)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.top, 8)
            .onChange(of: tab) { _, _ in
                Task { await search() }
            }

            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField(language.t("search.placeholder"), text: $keyword)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.search)
                    .onSubmit { Task { await search() } }
                if !keyword.isEmpty {
                    Button {
                        keyword = ""
                        spots = []
                        products = []
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            .padding(12)
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .padding()

            if isLoading {
                ProgressView().padding()
            }

            if let errorMessage {
                Text(errorMessage)
                    .foregroundStyle(.red)
                    .font(.caption)
                    .padding(.horizontal)
            }

            if tab == .spots {
                List(spots) { item in
                    NavigationLink {
                        LandmarkDetailView(spotId: item.point.resolvedId)
                    } label: {
                        NearbyRow(item: item)
                    }
                }
                .listStyle(.plain)
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
                                Text(product.name ?? "Product")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.primary)
                                Text(product.displayPrice)
                                    .font(.caption)
                                    .foregroundStyle(Color.accentColor)
                            }
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle(language.t("map.search"))
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(isPresented: Binding(
            get: { selectedProductId != nil },
            set: { if !$0 { selectedProductId = nil } }
        )) {
            if let selectedProductId {
                ProductDetailView(productId: selectedProductId)
            }
        }
        .onChange(of: keyword) { _, newValue in
            searchTask?.cancel()
            searchTask = Task {
                try? await Task.sleep(nanoseconds: 400_000_000)
                guard !Task.isCancelled else { return }
                await search()
            }
            if newValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                spots = []
                products = []
            }
        }
    }

    @MainActor
    private func search() async {
        let key = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            if tab == .spots {
                spots = try await SpotAPI.search(
                    latitude: latitude,
                    longitude: longitude,
                    keyword: key
                )
            } else {
                products = try await ProductAPI.search(keyword: key)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
