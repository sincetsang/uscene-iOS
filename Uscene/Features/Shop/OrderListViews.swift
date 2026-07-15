import SwiftUI

struct MyBuyOrdersView: View {
    @Environment(LanguageManager.self) private var language
    @State private var filter: OrderStatusFilter = .all
    @State private var items: [MarketplaceOrderRow] = []
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        orderList
            .navigationTitle(language.t("order.myBuy"))
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        ForEach(OrderStatusFilter.allCases) { item in
                            Button(item.title(language: language)) { filter = item }
                        }
                    } label: {
                        Label(filter.title(language: language), systemImage: "line.3.horizontal.decrease.circle")
                    }
                }
            }
            .onChange(of: filter) { _, _ in Task { await load() } }
            .task { await load() }
            .refreshable { await load() }
    }

    @ViewBuilder
    private var orderList: some View {
        if isLoading && items.isEmpty {
            ProgressView(language.t("common.loading"))
        } else if let errorMessage, items.isEmpty {
            ContentUnavailableView(language.t("common.error"), systemImage: "exclamationmark.triangle", description: Text(errorMessage))
        } else if items.isEmpty {
            ContentUnavailableView(language.t("order.empty"), systemImage: "bag")
        } else {
                List(items) { row in
                    if let id = row.resolvedOrderId {
                        NavigationLink {
                            OrderDetailView(orderId: id, kind: .product, isSeller: false)
                        } label: {
                            MarketplaceOrderRowView(row: row)
                        }
                    }
                }
                .listStyle(.plain)
        }
    }

    @MainActor
    private func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let pendingRefund = filter == .pendingRefundFlag ? 1 : 0
            let status = filter == .pendingRefundFlag ? "" : filter.rawValue
            items = try await CommerceAPI.bought(status: status, pendingRefund: pendingRefund).items ?? []
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct MySellOrdersView: View {
    @Environment(LanguageManager.self) private var language
    @State private var filter: OrderStatusFilter = .all
    @State private var items: [MarketplaceOrderRow] = []
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if isLoading && items.isEmpty {
                ProgressView(language.t("common.loading"))
            } else if let errorMessage, items.isEmpty {
                ContentUnavailableView(language.t("common.error"), systemImage: "exclamationmark.triangle", description: Text(errorMessage))
            } else if items.isEmpty {
                ContentUnavailableView(language.t("order.empty"), systemImage: "shippingbox")
            } else {
                List(items) { row in
                    if let id = row.resolvedOrderId {
                        NavigationLink {
                            OrderDetailView(orderId: id, kind: .product, isSeller: true)
                        } label: {
                            MarketplaceOrderRowView(row: row)
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle(language.t("order.mySell"))
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    ForEach(OrderStatusFilter.allCases) { item in
                        Button(item.title(language: language)) { filter = item }
                    }
                } label: {
                    Label(filter.title(language: language), systemImage: "line.3.horizontal.decrease.circle")
                }
            }
        }
        .onChange(of: filter) { _, _ in Task { await load() } }
        .task { await load() }
        .refreshable { await load() }
    }

    @MainActor
    private func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let pendingRefund = filter == .pendingRefundFlag ? 1 : 0
            let status = filter == .pendingRefundFlag ? "" : filter.rawValue
            items = try await CommerceAPI.sold(status: status, pendingRefund: pendingRefund).items ?? []
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct MyCodeOrdersView: View {
    @Environment(LanguageManager.self) private var language
    @State private var items: [CommerceOrder] = []
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if isLoading && items.isEmpty {
                ProgressView(language.t("common.loading"))
            } else if let errorMessage, items.isEmpty {
                ContentUnavailableView(language.t("common.error"), systemImage: "exclamationmark.triangle", description: Text(errorMessage))
            } else if items.isEmpty {
                ContentUnavailableView(language.t("order.empty"), systemImage: "ticket")
            } else {
                List(items) { order in
                    if order.resolvedId > 0 {
                        NavigationLink {
                            OrderDetailView(orderId: order.resolvedId, kind: .code)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(order.product_name ?? "Code Order").font(.headline)
                                Text(order.displayAmount).foregroundStyle(Color.accentColor)
                                Text(order.status ?? "-").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle(language.t("order.myCodes"))
        .task { await load() }
        .refreshable { await load() }
    }

    @MainActor
    private func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            items = try await CommerceAPI.codeOrders()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct MarketplaceOrderRowView: View {
    let row: MarketplaceOrderRow

    var body: some View {
        HStack(spacing: 12) {
            AsyncImage(url: URL(string: row.product?.cover ?? row.order?.head_img ?? "")) { phase in
                switch phase {
                case .success(let image): image.resizable().scaledToFill()
                default: Color.gray.opacity(0.12)
                }
            }
            .frame(width: 56, height: 56)
            .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 4) {
                Text(row.product?.name ?? row.order?.product_name ?? "Order")
                    .font(.headline)
                    .lineLimit(1)
                Text(row.order?.displayAmount ?? "-")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
                Text(row.order?.status ?? "-")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
