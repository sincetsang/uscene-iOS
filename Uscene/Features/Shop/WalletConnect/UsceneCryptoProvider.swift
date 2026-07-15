import Foundation

#if canImport(ReownAppKit)
import WalletConnectSigner

/// Minimal `CryptoProvider` for AppKit — keccak via local ABI helper; pubkey recovery unused for USDT pay.
struct UsceneCryptoProvider: CryptoProvider {
    func recoverPubKey(signature: EthereumSignature, message: Data) throws -> Data {
        throw CryptoProviderError.recoveryUnavailable
    }

    func keccak256(_ data: Data) -> Data {
        EthABI.keccak256(data)
    }

    enum CryptoProviderError: LocalizedError {
        case recoveryUnavailable
        var errorDescription: String? { "Ethereum pubkey recovery is not enabled in this build" }
    }
}
#endif
