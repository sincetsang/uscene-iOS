import SwiftUI
import UIKit

struct OrderDetailView: View {
    @Environment(LanguageManager.self) private var language
    @Environment(\.dismiss) private var dismiss

    let orderId: Int
    let kind: OrderKind
    var isSeller: Bool = false

    @State private var order: CommerceOrder?
    @State private var payInfo: PayInfo?
    @State private var isLoading = false
    @State private var isActing = false
    @State private var errorMessage: String?
    @State private var pollingTask: Task<Void, Never>?

    @State private var showRefundPrompt = false
    @State private var refundReason = ""
    @State private var showRejectRefund = false
    @State private var rejectReason = ""
    @State private var showPriceEditor = false
    @State private var priceText = ""
    @State private var showAddressEditor = false
    @State private var editName = ""
    @State private var editPhone = ""
    @State private var editAddress = ""
    @State private var showCommentSheet = false

    var body: some View {
        Group {
            if isLoading && order == nil {
                ProgressView(language.t("common.loading"))
            } else if let errorMessage, order == nil {
                ContentUnavailableView {
                    Label(language.t("common.error"), systemImage: "exclamationmark.triangle")
                } description: {
                    Text(errorMessage)
                } actions: {
                    Button(language.t("common.retry")) { Task { await load() } }
                }
            } else if let order {
                List {
                    Section(language.t("order.info")) {
                        LabeledContent("ID", value: "\(order.resolvedId > 0 ? order.resolvedId : orderId)")
                        LabeledContent(language.t("order.status"), value: order.status ?? "-")
                        LabeledContent(language.t("order.amount"), value: order.displayAmount)
                        if let refund = order.refund_info?.status ?? order.refund_status, !refund.isEmpty {
                            LabeledContent(language.t("order.refundStatus"), value: refund)
                        }
                        if let name = order.product_name ?? order.product?.name {
                            LabeledContent(language.t("shop.product"), value: name)
                        }
                        if let period = order.period {
                            LabeledContent(language.t("vip.period"), value: "\(period)")
                        }
                    }

                    if let contact = order.contact_info {
                        Section(language.t("shop.shipping")) {
                            LabeledContent(language.t("shop.contactName"), value: contact.contact_name ?? "-")
                            LabeledContent(language.t("shop.contactPhone"), value: contact.contact_phone ?? "-")
                            Text(contact.contact_address ?? "-")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }

                    if isUnpaid(order.status) {
                        Section(paySectionTitle(for: order)) {
                            if let payInfo {
                                if let address = payInfo.receiving_address, !address.isEmpty {
                                    LabeledContent(language.t("order.receiveAddress"), value: address)
                                    Button(language.t("common.copy")) {
                                        UIPasteboard.general.string = address
                                    }
                                }
                                if let value = payInfo.value {
                                    LabeledContent(language.t("order.payValue"), value: value)
                                }
                                if let contract = payInfo.contract_address {
                                    LabeledContent(language.t("order.contract"), value: contract)
                                        .font(.caption)
                                }
                                if let paycode = payInfo.paycode, !paycode.isEmpty {
                                    LabeledContent(language.t("order.paycode"), value: paycode)
                                        .font(.caption)
                                }

                                if isCryptoPay(order) {
                                    if !WalletConnectBootstrap.isSDKLinked {
                                        Text(language.t("order.walletConnectMissingSDK"))
                                            .font(.caption2)
                                            .foregroundStyle(.orange)
                                    }
                                    Button(language.t("order.connectWallet")) {
                                        CryptoPayService.ensureConnected()
                                    }
                                    .disabled(!WalletConnectBootstrap.isSDKLinked)
                                    Button(language.t("order.walletPay")) {
                                        Task { await walletConnectPay() }
                                    }
                                    .disabled(isActing || !WalletConnectBootstrap.isSDKLinked)
                                    Button(language.t("order.openWallet")) {
                                        Task {
                                            await WalletPayHelper.openExternalWallet(
                                                address: payInfo.receiving_address ?? "",
                                                amountRaw: payInfo.value,
                                                contract: payInfo.contract_address
                                            )
                                        }
                                    }
                                    Button(language.t("order.sharePay")) {
                                        WalletPayHelper.sharePayInfo(
                                            address: payInfo.receiving_address ?? "",
                                            amount: payInfo.value,
                                            contract: payInfo.contract_address
                                        )
                                    }
                                }

                                if isFECPay(order) {
                                    Button(language.t("order.uePay")) {
                                        Task { await uePay() }
                                    }
                                    .disabled(isActing || (payInfo.paycode ?? "").isEmpty)
                                    if !UEPayBridge.isSDKLinked {
                                        Text(language.t("order.uePayMissingSDK"))
                                            .font(.caption2)
                                            .foregroundStyle(.orange)
                                    }
                                }

                                Text(payHint(for: order))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            } else {
                                ProgressView()
                            }
                        }
                    }

                    Section {
                        if isUnpaid(order.status) {
                            Button(language.t("order.refreshPay")) {
                                Task { await refreshPay() }
                            }
                            Button(role: .destructive) {
                                Task { await cancel() }
                            } label: {
                                Text(language.t("order.cancel"))
                            }
                            .disabled(isActing)
                        }

                        if kind == .product, !isSeller, canBuyerRefund(order.status) {
                            Button(language.t("order.applyRefund")) {
                                refundReason = ""
                                showRefundPrompt = true
                            }
                            .disabled(isActing)
                        }

                        if kind == .product, !isSeller, order.status == "pending_receipt" {
                            Button(language.t("order.confirmReceipt")) {
                                Task { await receipt() }
                            }
                            .disabled(isActing)
                        }

                        if kind == .product, !isSeller, canEditAddress(order.status) {
                            Button(language.t("order.updateAddress")) {
                                editName = order.contact_info?.contact_name ?? ""
                                editPhone = order.contact_info?.contact_phone ?? ""
                                editAddress = order.contact_info?.contact_address ?? ""
                                showAddressEditor = true
                            }
                            .disabled(isActing)
                        }

                        if kind == .product, isSeller, order.status == "pending_shipment" || order.status == "paid" {
                            Button(language.t("order.confirmShipment")) {
                                Task { await ship() }
                            }
                            .disabled(isActing)
                        }

                        if kind == .product, isSeller, canSellerCancel(order.status) {
                            Button(role: .destructive) {
                                Task { await merchantCancel() }
                            } label: {
                                Text(language.t("order.merchantCancel"))
                            }
                            .disabled(isActing)
                        }

                        if kind == .product, isSeller, canSellerEditPrice(order.status) {
                            Button(language.t("order.updatePrice")) {
                                priceText = order.amount.map { String(format: "%g", $0) } ?? ""
                                showPriceEditor = true
                            }
                            .disabled(isActing)
                        }

                        if kind == .product, isSeller, let refundId = order.resolvedRefundId {
                            Button(language.t("order.approveRefund")) {
                                Task { await handleRefund(refundId: refundId, approve: true) }
                            }
                            .disabled(isActing)
                            Button(role: .destructive) {
                                rejectReason = ""
                                showRejectRefund = true
                            } label: {
                                Text(language.t("order.rejectRefund"))
                            }
                            .disabled(isActing)
                        }

                        if kind == .product, !isSeller, canComment(order) {
                            Button(language.t("comment.write")) {
                                showCommentSheet = true
                            }
                            .disabled(isActing)
                        }

                        if kind == .product, canDelete(order.status) {
                            Button(role: .destructive) {
                                Task { await deleteOrder() }
                            } label: {
                                Text(language.t("order.delete"))
                            }
                            .disabled(isActing)
                        }
                    }

                    if let errorMessage {
                        Section { Text(errorMessage).foregroundStyle(.red) }
                    }
                }
            } else {
                ContentUnavailableView(
                    language.t("common.error"),
                    systemImage: "doc.questionmark",
                    description: Text(language.t("order.empty"))
                )
            }
        }
        .navigationTitle(language.t("order.detail"))
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await load()
            startPollingIfNeeded()
        }
        .onDisappear { pollingTask?.cancel() }
        .refreshable { await load() }
        .alert(language.t("order.applyRefund"), isPresented: $showRefundPrompt) {
            TextField(language.t("order.refundReason"), text: $refundReason)
            Button(language.t("common.cancel"), role: .cancel) {}
            Button(language.t("common.done")) {
                Task { await applyRefund() }
            }
        } message: {
            Text(language.t("order.refundHint"))
        }
        .alert(language.t("order.rejectRefund"), isPresented: $showRejectRefund) {
            TextField(language.t("order.rejectReason"), text: $rejectReason)
            Button(language.t("common.cancel"), role: .cancel) {}
            Button(language.t("common.done")) {
                if let refundId = order?.resolvedRefundId {
                    Task { await handleRefund(refundId: refundId, approve: false) }
                }
            }
        }
        .alert(language.t("order.updatePrice"), isPresented: $showPriceEditor) {
            TextField(language.t("product.priceAmount"), text: $priceText)
                .keyboardType(.decimalPad)
            Button(language.t("common.cancel"), role: .cancel) {}
            Button(language.t("common.done")) {
                Task { await updatePrice() }
            }
        }
        .sheet(isPresented: $showAddressEditor) {
            NavigationStack {
                Form {
                    TextField(language.t("shop.contactName"), text: $editName)
                    TextField(language.t("shop.contactPhone"), text: $editPhone)
                        .keyboardType(.phonePad)
                    TextField(language.t("shop.contactAddress"), text: $editAddress, axis: .vertical)
                        .lineLimit(2...4)
                }
                .navigationTitle(language.t("order.updateAddress"))
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(language.t("common.cancel")) { showAddressEditor = false }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button(language.t("common.done")) {
                            Task { await updateAddress() }
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $showCommentSheet) {
            NavigationStack {
                OrderCommentView(orderId: orderId, isEdit: order?.is_commented == true) {
                    showCommentSheet = false
                    Task { await load() }
                }
            }
        }
    }

    private func canComment(_ order: CommerceOrder) -> Bool {
        let status = (order.status ?? "").lowercased()
        return status == "completed" && order.is_commented != true
    }

    private func isUnpaid(_ status: String?) -> Bool {
        let value = (status ?? "").lowercased()
        return value == "unpaid" || value == "pending_payment" || value == "payment_processing"
    }

    private func payCurrency(for order: CommerceOrder) -> String {
        let unit = (order.unit ?? order.currency ?? order.pay_type ?? "USDT").uppercased()
        if unit == "ETH" { return "USDT" }
        return unit
    }

    private func isCryptoPay(_ order: CommerceOrder) -> Bool {
        let currency = payCurrency(for: order)
        return currency == "USDT" || currency == "ETH"
    }

    private func isFECPay(_ order: CommerceOrder) -> Bool {
        payCurrency(for: order) == "FEC"
    }

    private func paySectionTitle(for order: CommerceOrder) -> String {
        let currency = payCurrency(for: order)
        if currency == "FEC" { return language.t("order.payFEC") }
        return language.t("order.payUSDT")
    }

    private func payHint(for order: CommerceOrder) -> String {
        if isFECPay(order) { return language.t("order.payHintFEC") }
        if isCryptoPay(order) { return language.t("order.payHintWalletConnect") }
        return language.t("order.payHint")
    }

    private func canBuyerRefund(_ status: String?) -> Bool {
        let value = (status ?? "").lowercased()
        return ["paid", "pending_shipment", "pending_receipt", "shipped"].contains(value)
            && order?.resolvedRefundId == nil
    }

    private func canEditAddress(_ status: String?) -> Bool {
        let value = (status ?? "").lowercased()
        return ["unpaid", "pending_payment", "paid", "pending_shipment"].contains(value)
    }

    private func canSellerCancel(_ status: String?) -> Bool {
        let value = (status ?? "").lowercased()
        return ["unpaid", "pending_payment", "paid", "pending_shipment"].contains(value)
    }

    private func canSellerEditPrice(_ status: String?) -> Bool {
        isUnpaid(status)
    }

    private func canDelete(_ status: String?) -> Bool {
        let value = (status ?? "").lowercased()
        return ["cancelled", "canceled", "completed", "refunded"].contains(value)
    }

    @MainActor
    private func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            switch kind {
            case .product:
                order = try await CommerceAPI.productOrderDetail(orderId: orderId, isSeller: isSeller ? 1 : 0)
            case .code:
                order = try await CommerceAPI.codeOrderDetail(orderId: orderId)
            case .member:
                order = try await CommerceAPI.memberOrderDetail(orderId: orderId)
            }
            if isUnpaid(order?.status) {
                await refreshPay()
            } else {
                payInfo = nil
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func refreshPay() async {
        do {
            switch kind {
            case .product:
                payInfo = try await CommerceAPI.productPayInfo(orderId: orderId)
            case .code:
                payInfo = try await CommerceAPI.codePayInfo(orderId: orderId)
            case .member:
                payInfo = try await CommerceAPI.memberPayInfo(orderId: orderId)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func walletConnectPay() async {
        guard let payInfo else { return }
        isActing = true
        defer { isActing = false }
        do {
            try await CryptoPayService.pay(with: payInfo, memoOrderId: orderId)
            if kind == .product {
                try? await CommerceAPI.productPayReport(orderId: orderId)
            }
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func uePay() async {
        guard let paycode = payInfo?.paycode else {
            errorMessage = language.t("order.uePayMissingSDK")
            return
        }
        isActing = true
        defer { isActing = false }
        do {
            UEPayBridge.shared.configure()
            _ = try await UEPayBridge.shared.pay(paycode: paycode, orderId: orderId)
            if kind == .product {
                try? await CommerceAPI.productPayReport(orderId: orderId)
            }
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func startPollingIfNeeded() {
        pollingTask?.cancel()
        pollingTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                guard !Task.isCancelled else { break }
                await pollStatus()
            }
        }
    }

    @MainActor
    private func pollStatus() async {
        guard isUnpaid(order?.status) else { return }
        do {
            let status: PayStatus
            switch kind {
            case .product:
                status = try await CommerceAPI.productPayStatus(orderId: orderId)
                if (status.status ?? "").lowercased() != "unpaid" {
                    try? await CommerceAPI.productPayReport(orderId: orderId)
                }
            case .code:
                status = try await CommerceAPI.codePayStatus(orderId: orderId)
            case .member:
                status = try await CommerceAPI.memberPayStatus(orderId: orderId)
            }
            if !isUnpaid(status.status) {
                await load()
            }
        } catch {
            // keep polling quietly
        }
    }

    @MainActor
    private func cancel() async {
        isActing = true
        defer { isActing = false }
        do {
            switch kind {
            case .product:
                try await CommerceAPI.cancelProductOrder(orderId: orderId)
            case .member:
                try await CommerceAPI.cancelMemberOrder(orderId: orderId)
            case .code:
                try await CommerceAPI.cancelCodeOrder(orderId: orderId)
            }
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func merchantCancel() async {
        isActing = true
        defer { isActing = false }
        do {
            try await CommerceAPI.cancelByMerchant(orderId: orderId)
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func applyRefund() async {
        isActing = true
        defer { isActing = false }
        do {
            try await CommerceAPI.applyRefund(orderId: orderId, reason: refundReason)
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func handleRefund(refundId: Int, approve: Bool) async {
        isActing = true
        defer { isActing = false }
        do {
            try await CommerceAPI.handleRefund(
                refundId: refundId,
                approve: approve,
                rejectReason: approve ? "" : rejectReason
            )
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func updatePrice() async {
        guard let price = Double(priceText.trimmingCharacters(in: .whitespacesAndNewlines)), price > 0 else {
            errorMessage = language.t("product.requirePrice")
            return
        }
        isActing = true
        defer { isActing = false }
        do {
            try await CommerceAPI.updateOrderPrice(orderId: orderId, price: price)
            showPriceEditor = false
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func updateAddress() async {
        guard !editName.trimmingCharacters(in: .whitespaces).isEmpty,
              !editPhone.trimmingCharacters(in: .whitespaces).isEmpty,
              !editAddress.trimmingCharacters(in: .whitespaces).isEmpty else {
            errorMessage = language.t("shop.requireAddress")
            return
        }
        isActing = true
        defer { isActing = false }
        do {
            try await CommerceAPI.updateOrderAddress(
                orderId: orderId,
                name: editName.trimmingCharacters(in: .whitespacesAndNewlines),
                phone: editPhone.trimmingCharacters(in: .whitespacesAndNewlines),
                address: editAddress.trimmingCharacters(in: .whitespacesAndNewlines)
            )
            showAddressEditor = false
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func deleteOrder() async {
        isActing = true
        defer { isActing = false }
        do {
            try await CommerceAPI.deleteOrder(orderId: orderId)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func receipt() async {
        isActing = true
        defer { isActing = false }
        do {
            try await CommerceAPI.confirmReceipt(orderId: orderId)
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func ship() async {
        isActing = true
        defer { isActing = false }
        do {
            try await CommerceAPI.confirmShipment(orderId: orderId)
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
