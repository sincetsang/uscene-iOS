import SwiftUI

struct CreateCodeOrderView: View {
    @Environment(LanguageManager.self) private var language
    @Environment(\.dismiss) private var dismiss

    let product: ProductDetail

    @State private var quantity = 1
    @State private var currency = "USDT"
    @State private var isSubmitting = false
    @State private var errorMessage: String?
    @State private var createdOrderId: Int?

    private var unitPrice: Double {
        if currency == "USDT" {
            return product.amount_usd ?? 0
        }
        return product.amount ?? 0
    }

    private var totalPrice: Double { unitPrice * Double(quantity) }

    private var payType: String { currency == "USDT" ? "ETH" : "FEC" }

    var body: some View {
        Form {
            Section {
                HStack(spacing: 12) {
                    AsyncImage(url: URL(string: product.cover ?? "")) { phase in
                        switch phase {
                        case .success(let image): image.resizable().scaledToFill()
                        default: Color.gray.opacity(0.12)
                        }
                    }
                    .frame(width: 88, height: 64)
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                    VStack(alignment: .leading, spacing: 6) {
                        Text(product.name ?? "Package")
                            .font(.headline)
                            .lineLimit(2)
                        if let num = product.check_code_num {
                            Text("\(language.t("shop.codeNum")): \(num)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Text(String(format: "%.2f %@", unitPrice, currency))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color.accentColor)
                    }
                }
            }

            if let desc = product.description, !desc.isEmpty {
                Section(language.t("product.description")) {
                    Text(desc).font(.subheadline).foregroundStyle(.secondary)
                }
            }

            Section(language.t("shop.quantity")) {
                Stepper(value: $quantity, in: 1...99) {
                    Text("\(quantity)")
                }
            }

            Section(language.t("shop.orderCurrency")) {
                Picker(language.t("shop.orderCurrency"), selection: $currency) {
                    Text("USDT").tag("USDT")
                    Text("FEC").tag("FEC")
                }
                .pickerStyle(.segmented)
            }

            Section(language.t("shop.orderAmount")) {
                Text(String(format: "%.2f %@", totalPrice, currency))
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
            }

            if let errorMessage {
                Section { Text(errorMessage).foregroundStyle(.red) }
            }
        }
        .navigationTitle(language.t("shop.createOrder"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(language.t("shop.placeOrder")) {
                    Task { await submit() }
                }
                .disabled(isSubmitting || unitPrice <= 0)
            }
        }
        .overlay {
            if isSubmitting {
                ProgressView().padding().background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            }
        }
        .navigationDestination(item: $createdOrderId) { orderId in
            OrderDetailView(orderId: orderId, kind: .code)
        }
    }

    @MainActor
    private func submit() async {
        errorMessage = nil
        guard let productId = product.product_id ?? Optional(product.id), productId > 0 else {
            errorMessage = language.t("common.error")
            return
        }
        guard unitPrice > 0 else {
            errorMessage = language.t("shop.orderAmountError")
            return
        }

        isSubmitting = true
        defer { isSubmitting = false }
        do {
            let order = try await CommerceAPI.createCodeOrder(
                CreateCodeOrderBody(
                    product_id: productId,
                    pay_type: payType,
                    currency: currency,
                    num: quantity
                )
            )
            let oid = order.resolvedId
            if oid > 0 {
                createdOrderId = oid
            } else {
                dismiss()
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
