import Foundation
import UIKit

#if canImport(ReownAppKit)
import ReownAppKit

@MainActor
enum WalletConnectBootstrap {
    static var isSDKLinked: Bool { true }

    private static var didConfigure = false

    static func configureIfNeeded() {
        guard !didConfigure else { return }
        didConfigure = true

        let metadata = AppMetadata(
            name: "Uscene",
            description: "Uscene marketplace & check-in",
            url: AppConfig.walletRedirectUniversal,
            icons: ["https://boring-test.web.app/favicon.ico"],
            redirect: try! AppMetadata.Redirect(
                native: AppConfig.walletRedirectNative,
                universal: AppConfig.walletRedirectUniversal
            )
        )

        let methods: Set<String> = ["eth_sendTransaction", "personal_sign", "eth_signTypedData"]
        let events: Set<String> = ["chainChanged", "accountsChanged"]
        let chainRef = "eip155:\(AppConfig.ethChainId)"
        let namespaces: [String: ProposalNamespace] = [
            "eip155": ProposalNamespace(
                chains: [Blockchain(chainRef)!],
                methods: methods,
                events: events
            )
        ]
        let sessionParams = SessionParams(
            namespaces: namespaces,
            sessionProperties: nil
        )

        AppKit.configure(
            projectId: AppConfig.walletConnectProjectId,
            metadata: metadata,
            crypto: UsceneCryptoProvider(),
            sessionParams: sessionParams,
            authRequestParams: nil,
            coinbaseEnabled: false
        )
    }

    static func presentConnect() {
        configureIfNeeded()
        AppKit.present()
    }

    static func handle(url: URL) {
        configureIfNeeded()
        AppKit.instance.handleDeeplink(url)
    }

    static var connectedAddress: String? {
        configureIfNeeded()
        guard let session = AppKit.instance.getSessions().first else { return nil }
        return session.namespaces.values
            .flatMap(\.accounts)
            .first?
            .address
    }

    static var hasSession: Bool {
        configureIfNeeded()
        return !AppKit.instance.getSessions().isEmpty
    }
}

/// USDT approve + proxy transferWithMemo via WalletConnect eth_sendTransaction.
@MainActor
enum CryptoPayService {
    enum PayError: LocalizedError {
        case notConnected
        case missingPayFields
        case requestFailed(String)
        case sdkUnavailable

        var errorDescription: String? {
            switch self {
            case .notConnected: return "Wallet not connected"
            case .missingPayFields: return "Incomplete pay info"
            case .requestFailed(let message): return message
            case .sdkUnavailable: return "WalletConnect (Reown) SPM not linked yet"
            }
        }
    }

    static func ensureConnected() {
        WalletConnectBootstrap.configureIfNeeded()
        if !WalletConnectBootstrap.hasSession {
            WalletConnectBootstrap.presentConnect()
        }
    }

    static func pay(with info: PayInfo, memoOrderId: Int) async throws {
        WalletConnectBootstrap.configureIfNeeded()
        guard let session = AppKit.instance.getSessions().first,
              let from = WalletConnectBootstrap.connectedAddress,
              !from.isEmpty
        else {
            WalletConnectBootstrap.presentConnect()
            throw PayError.notConnected
        }
        guard let receiving = info.receiving_address, !receiving.isEmpty,
              let proxy = info.contract_address, !proxy.isEmpty,
              let value = info.value, !value.isEmpty
        else {
            throw PayError.missingPayFields
        }

        let amount = BigUIntHex(decimalString: value)
        let chainId = Blockchain("eip155:\(AppConfig.ethChainId)")!

        let approveData = EthABI.encodeApprove(spender: proxy, amount: amount)
        try await sendTransaction(
            sessionTopic: session.topic,
            from: from,
            to: AppConfig.usdtContractAddress,
            data: approveData,
            chainId: chainId
        )

        try await Task.sleep(nanoseconds: 1_500_000_000)

        let memo = "\(memoOrderId)"
        let transferData = EthABI.encodeTransferWithMemo(
            token: AppConfig.usdtContractAddress,
            to: receiving,
            amount: amount,
            memo: memo
        )
        try await sendTransaction(
            sessionTopic: session.topic,
            from: from,
            to: proxy,
            data: transferData,
            chainId: chainId
        )
    }

    private static func sendTransaction(
        sessionTopic: String,
        from: String,
        to: String,
        data: Data,
        chainId: Blockchain
    ) async throws {
        let tx: [String: String] = [
            "from": from,
            "to": to,
            "value": "0x0",
            "data": "0x" + data.map { String(format: "%02x", $0) }.joined(),
            "gas": "0x186a0"
        ]
        do {
            try await AppKit.instance.request(
                params: Request(
                    topic: sessionTopic,
                    method: "eth_sendTransaction",
                    params: AnyCodable([tx]),
                    chainId: chainId
                )
            )
            AppKit.instance.launchCurrentWallet()
        } catch {
            throw PayError.requestFailed(error.localizedDescription)
        }
    }
}

#else

/// Stub until Reown SPM packages resolve (see `Vendor/README.md` / Phase 12).
@MainActor
enum WalletConnectBootstrap {
    static var isSDKLinked: Bool { false }
    static func configureIfNeeded() {}
    static func presentConnect() {}
    static func handle(url: URL) {}
    static var connectedAddress: String? { nil }
    static var hasSession: Bool { false }
}

@MainActor
enum CryptoPayService {
    enum PayError: LocalizedError {
        case sdkUnavailable
        var errorDescription: String? {
            "WalletConnect (Reown) is not linked. Enable the reown SPM package in project.yml once yttrium binaries download (see Vendor/README.md)."
        }
    }

    static func ensureConnected() {}

    static func pay(with info: PayInfo, memoOrderId: Int) async throws {
        throw PayError.sdkUnavailable
    }
}

#endif
