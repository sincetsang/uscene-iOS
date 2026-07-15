import Foundation
import UIKit

/// Thin bridge around the proprietary UE Token iOS SDK (`Vendor/UESDKProject.framework`).
@MainActor
final class UEPayBridge: NSObject {
    static let shared = UEPayBridge()

    static var isSDKLinked: Bool { UEPayObjCBridge.isAvailable() }

    enum UEPayError: LocalizedError {
        case sdkMissing
        case missingPaycode
        case failed(String)

        var errorDescription: String? {
            switch self {
            case .sdkMissing:
                return "UE Pay iOS SDK is not available (device build required; see Vendor/README.md)."
            case .missingPaycode:
                return "Missing paycode"
            case .failed(let message):
                return message
            }
        }
    }

    func configure() {
        guard Self.isSDKLinked else { return }
        UEPayObjCBridge.configure(
            withLogo: AppConfig.ueStoreLogo,
            storeName: AppConfig.ueStoreName,
            scheme: AppConfig.ueScheme,
            beta: AppConfig.isTestAPI
        )
    }

    func handleOpenURL(_ url: URL) -> Bool {
        guard Self.isSDKLinked else { return false }
        return UEPayObjCBridge.handleUEOpen(url)
    }

    func pay(paycode: String, orderId: Int) async throws {
        guard Self.isSDKLinked else { throw UEPayError.sdkMissing }
        let code = paycode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !code.isEmpty else { throw UEPayError.missingPaycode }
        guard let target = Self.topViewController() else {
            throw UEPayError.failed("Missing view controller for UE Pay")
        }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            UEPayObjCBridge.combinedPay(
                withPaycode: code,
                orderNo: "\(orderId)",
                target: target
            ) { success, message in
                if success {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: UEPayError.failed(message ?? "UE Pay failed"))
                }
            }
        }
    }

    private static func topViewController(
        base: UIViewController? = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)?
            .rootViewController
    ) -> UIViewController? {
        if let nav = base as? UINavigationController {
            return topViewController(base: nav.visibleViewController)
        }
        if let tab = base as? UITabBarController {
            return topViewController(base: tab.selectedViewController)
        }
        if let presented = base?.presentedViewController {
            return topViewController(base: presented)
        }
        return base
    }
}
