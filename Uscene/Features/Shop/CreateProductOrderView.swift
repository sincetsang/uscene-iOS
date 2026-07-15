import SwiftUI

struct CreateProductOrderView: View {
    @Environment(LanguageManager.self) private var language
    @Environment(\.dismiss) private var dismiss

    let product: ProductDetail

    @State private var contactName = ""
    @State private var contactPhone = ""
    @State private var contactAddress = ""
    @State private var quantity = 1
    @State private var currency = "USDT"
    @State private var isSubmitting = false
    @State private var errorMessage: String?
    @State private var createdOrderId: Int?
    @State private var showAddressPicker = false

    private var unitPrice: Double {
        currency == "USDT" ? (product.amount_usd ?? 0) : (product.amount ?? 0)
    }

    private var totalPrice: Double { unitPrice * Double(quantity) }
    private var payType: String { currency == "USDT" ? "ETH" : "FEC" }

    var body: some View {
        Form {
            Section(product.name ?? "Product") {
                Text(String(format: "%.2f %@", unitPrice, currency))
                    .foregroundStyle(Color.accentColor)
                Text(language.t("shop.payUSDTOnly"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
                Text("\(language.t("shop.orderAmount")): \(String(format: "%.2f %@", totalPrice, currency))")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
            }

            Section(language.t("shop.shipping")) {
                Button {
                    showAddressPicker = true
                } label: {
                    Label(language.t("address.pick"), systemImage: "book.closed")
                }

                TextField(language.t("shop.contactName"), text: $contactName)
                TextField(language.t("shop.contactPhone"), text: $contactPhone)
                    .keyboardType(.phonePad)
                TextField(language.t("shop.contactAddress"), text: $contactAddress, axis: .vertical)
                    .lineLimit(2...4)
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
                .disabled(isSubmitting)
            }
        }
        .overlay {
            if isSubmitting {
                ProgressView().padding().background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            }
        }
        .navigationDestination(item: $createdOrderId) { orderId in
            OrderDetailView(orderId: orderId, kind: .product)
        }
        .sheet(isPresented: $showAddressPicker) {
            NavigationStack {
                MyAddressView { address in
                    contactName = address.name ?? ""
                    contactPhone = address.phone ?? ""
                    contactAddress = address.fullAddress
                    showAddressPicker = false
                }
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(language.t("common.cancel")) { showAddressPicker = false }
                    }
                }
            }
        }
        .task { await preloadDefaultAddress() }
    }

    @MainActor
    private func preloadDefaultAddress() async {
        guard contactName.isEmpty, contactPhone.isEmpty, contactAddress.isEmpty else { return }
        guard let list = try? await CommerceAPI.addressList() else { return }
        let preferred = list.first(where: \.isDefault) ?? list.first
        guard let preferred else { return }
        contactName = preferred.name ?? ""
        contactPhone = preferred.phone ?? ""
        contactAddress = preferred.fullAddress
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
        guard !contactName.trimmingCharacters(in: .whitespaces).isEmpty,
              !contactPhone.trimmingCharacters(in: .whitespaces).isEmpty,
              !contactAddress.trimmingCharacters(in: .whitespaces).isEmpty else {
            errorMessage = language.t("shop.requireAddress")
            return
        }

        isSubmitting = true
        defer { isSubmitting = false }
        do {
            let order = try await CommerceAPI.createProductOrder(
                CreateProductOrderBody(
                    product_id: productId,
                    pay_type: payType,
                    currency: currency,
                    num: quantity,
                    contact_name: contactName.trimmingCharacters(in: .whitespacesAndNewlines),
                    contact_phone: contactPhone.trimmingCharacters(in: .whitespacesAndNewlines),
                    contact_address: contactAddress.trimmingCharacters(in: .whitespacesAndNewlines)
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
