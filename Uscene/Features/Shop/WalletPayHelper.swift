import Foundation
import UIKit

enum OrderStatusFilter: String, CaseIterable, Identifiable {
    case all = ""
    case pendingPayment = "pending_payment"
    case pendingShipment = "pending_shipment"
    case pendingReceipt = "pending_receipt"
    case completed = "completed"
    case cancelled = "cancelled"
    case refundInProgress = "refund_in_progress"
    case refunded = "refunded"
    case pendingRefundFlag = "__pending_refund__"

    var id: String { rawValue.isEmpty ? "all" : rawValue }

    @MainActor
    func title(language: LanguageManager) -> String {
        switch self {
        case .all: return language.t("order.filterAll")
        case .pendingPayment: return language.t("order.statusPendingPayment")
        case .pendingShipment: return language.t("order.statusPendingShipment")
        case .pendingReceipt: return language.t("order.statusPendingReceipt")
        case .completed: return language.t("order.statusCompleted")
        case .cancelled: return language.t("order.statusCancelled")
        case .refundInProgress: return language.t("order.statusRefundProgress")
        case .refunded: return language.t("order.statusRefunded")
        case .pendingRefundFlag: return language.t("order.filterRefund")
        }
    }
}

enum WalletPayHelper {
    static func sharePayInfo(address: String, amount: String?, contract: String?) {
        var lines = [
            "USDT",
            address
        ]
        if let amount, !amount.isEmpty {
            lines.append(amount)
        }
        if let contract, !contract.isEmpty {
            lines.append(contract)
        }
        let text = lines.joined(separator: "\n")
        let activity = UIActivityViewController(activityItems: [text], applicationActivities: nil)
        present(activity)
    }

    @MainActor
    static func openExternalWallet(address: String, amountRaw: String?, contract: String?) async {
        var candidates: [URL] = []

        if let contract, !contract.isEmpty,
           let amountRaw, !amountRaw.isEmpty,
           let encoded = amountRaw.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
            let mm = "https://metamask.app.link/send/\(contract)@1/transfer?address=\(address)&uint256=\(encoded)"
            if let url = URL(string: mm) { candidates.append(url) }
        }

        if let url = URL(string: "https://metamask.app.link/send/\(address)") {
            candidates.append(url)
        }

        for url in candidates {
            let opened = await UIApplication.shared.open(url)
            if opened { return }
        }

        UIPasteboard.general.string = address
    }

    private static func present(_ controller: UIViewController) {
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let root = scene.keyWindow?.rootViewController else { return }
        var presenter = root
        while let presented = presenter.presentedViewController {
            presenter = presented
        }
        presenter.present(controller, animated: true)
    }
}

private extension UIWindowScene {
    var keyWindow: UIWindow? {
        windows.first(where: \.isKeyWindow) ?? windows.first
    }
}
