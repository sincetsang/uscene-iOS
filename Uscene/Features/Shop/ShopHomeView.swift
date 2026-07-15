import SwiftUI

struct ShopHomeView: View {
    @Environment(LanguageManager.self) private var language
    @State private var products: [ShopProduct] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var selectedProductId: Int?

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                Text(language.t("shop.shop"))
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(Color(red: 0.2, green: 0.2, blue: 0.2))
                    .frame(height: 44)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .tabRootHeaderInset()

                promoBar
                    .padding(.top, 80)
                    .padding(.horizontal, 20)

                groupBuySection
                    .padding(.top, 24)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 24)
            }
            .frame(maxWidth: .infinity)
            .background(alignment: .top) {
                Image("ShopTop")
                    .resizable()
                    .scaledToFill()
                    .frame(height: 340)
                    .frame(maxWidth: .infinity)
                    .clipped()
            }
        }
        .background(Color.white)
        .tabRootChrome()
        .navigationDestination(isPresented: Binding(
            get: { selectedProductId != nil },
            set: { if !$0 { selectedProductId = nil } }
        )) {
            if let selectedProductId {
                ProductDetailView(productId: selectedProductId)
            }
        }
        .refreshable { await load() }
        .task { await load() }
    }

    private var promoBar: some View {
        HStack(spacing: 6) {
            Image("Trumpet")
                .resizable()
                .scaledToFit()
                .frame(width: 14, height: 14)
            Text(language.t("shop.promoBanner"))
                .font(.system(size: 13))
                .foregroundStyle(.black)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(4)
        .padding(.horizontal, 8)
        .frame(height: 42)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 6))
        .shadow(color: .black.opacity(0.06), radius: 4, y: 2)
    }

    private var groupBuySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Capsule()
                    .fill(Theme.shopBar)
                    .frame(width: 3, height: 16)
                Text(language.t("shop.groupBuy"))
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Color(red: 0.2, green: 0.2, blue: 0.2))
            }

            if isLoading && products.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
            } else if let errorMessage, products.isEmpty {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.vertical, 20)
            } else if products.isEmpty {
                Text(language.t("shop.empty"))
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 20)
            } else {
                ForEach(products) { product in
                    ShopProductRow(product: product) {
                        selectedProductId = product.id
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 8)
        .background(Color.white)
    }

    @MainActor
    private func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            products = try await ProductAPI.list()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct ShopProductRow: View {
    @Environment(LanguageManager.self) private var language
    let product: ShopProduct
    let onBuy: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 8) {
                AsyncImage(url: URL(string: product.cover ?? "")) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    default:
                        Image("CodeAvatar").resizable().scaledToFill()
                    }
                }
                .frame(width: 120, height: 70)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .padding(10)
                .background(
                    Color(red: 0.965, green: 0.957, blue: 0.961),
                    in: RoundedRectangle(cornerRadius: 10)
                )

                VStack(alignment: .leading, spacing: 12) {
                    Text(product.name ?? "Product")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color(red: 0.2, green: 0.2, blue: 0.2))
                        .lineLimit(1)

                    Text("\(language.t("shop.codeNum"))：\(product.check_code_num ?? 0)")
                        .font(.system(size: 12))
                        .foregroundStyle(.black)

                    HStack {
                        Text(product.displayPrice)
                            .font(.system(size: 20, weight: .medium))
                            .foregroundStyle(Theme.shop)

                        Spacer()

                        Button(action: onBuy) {
                            Text("$ \(language.t("shop.buyNow"))")
                                .font(.system(size: 14))
                                .foregroundStyle(.white)
                                .frame(width: 88, height: 32)
                                .background(Theme.shop, in: Capsule())
                                .shadow(color: Theme.shop.opacity(0.25), radius: 6, y: 2)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.vertical, 16)

            Divider().overlay(Color(red: 0.863, green: 0.886, blue: 0.937))
        }
    }
}
