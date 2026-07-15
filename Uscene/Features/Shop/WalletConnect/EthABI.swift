import Foundation

/// Minimal Ethereum ABI helpers for approve + transferWithMemo.
enum EthABI {
    static let approveSelector = Data([0x09, 0x5e, 0xa7, 0xb3]) // approve(address,uint256)
    // keccak256("transferWithMemo(address,address,uint256,string)")[0..<4]
    static let transferWithMemoSelector = Data(hexString: selectorHex("transferWithMemo(address,address,uint256,string)"))!

    static func encodeApprove(spender: String, amount: BigUIntHex) -> Data {
        var data = approveSelector
        data.append(padAddress(spender))
        data.append(padUInt256(amount.hex))
        return data
    }

    static func encodeTransferWithMemo(
        token: String,
        to: String,
        amount: BigUIntHex,
        memo: String
    ) -> Data {
        var data = transferWithMemoSelector
        data.append(padAddress(token))
        data.append(padAddress(to))
        data.append(padUInt256(amount.hex))
        // dynamic string: offset to head (4 args * 32) from start of params = 0x80
        data.append(padUInt256("80"))
        let memoData = Data(memo.utf8)
        data.append(padUInt256(String(memoData.count, radix: 16)))
        data.append(padBytes(memoData))
        return data
    }

    static func padAddress(_ address: String) -> Data {
        var hex = address.lowercased().replacingOccurrences(of: "0x", with: "")
        if hex.count > 40 { hex = String(hex.suffix(40)) }
        return padUInt256(hex)
    }

    static func padUInt256(_ hex: String) -> Data {
        var cleaned = hex.lowercased().replacingOccurrences(of: "0x", with: "")
        if cleaned.count > 64 {
            cleaned = String(cleaned.suffix(64))
        }
        let padded = String(repeating: "0", count: max(0, 64 - cleaned.count)) + cleaned
        return Data(hexString: padded) ?? Data(count: 32)
    }

    static func padBytes(_ bytes: Data) -> Data {
        var out = bytes
        let rem = out.count % 32
        if rem != 0 {
            out.append(Data(count: 32 - rem))
        }
        return out
    }

    static func selectorHex(_ signature: String) -> String {
        let digest = keccak256(Data(signature.utf8))
        return digest.prefix(4).map { String(format: "%02x", $0) }.joined()
    }

    /// Keccak-256 (not SHA3-256). Compact implementation for ABI selectors / hashing.
    static func keccak256(_ data: Data) -> Data {
        Keccak256.hash(data)
    }
}

struct BigUIntHex {
    let hex: String

    init(decimalString: String) {
        // PayInfo.value from API is typically raw integer string (USDT 6 decimals).
        if decimalString.hasPrefix("0x") || decimalString.hasPrefix("0X") {
            hex = String(decimalString.dropFirst(2))
            return
        }
        hex = Self.decimalToHex(decimalString) ?? "0"
    }

    init(hex: String) {
        self.hex = hex.replacingOccurrences(of: "0x", with: "").replacingOccurrences(of: "0X", with: "")
    }

    var hexPrefixed: String { "0x\(hex)" }

    private static func decimalToHex(_ decimal: String) -> String? {
        let trimmed = decimal.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.allSatisfy(\.isNumber) else { return nil }
        var value = Array(trimmed.utf8).map { Int($0 - 48) }
        var hexDigits: [Character] = []
        while !(value.count == 1 && value[0] == 0) {
            var remainder = 0
            var next: [Int] = []
            for digit in value {
                let current = remainder * 10 + digit
                let q = current / 16
                remainder = current % 16
                if !(next.isEmpty && q == 0) {
                    next.append(q)
                }
            }
            hexDigits.append(Character(String(remainder, radix: 16)))
            value = next.isEmpty ? [0] : next
        }
        return String(hexDigits.reversed())
    }
}

private enum Keccak256 {
    // Based on public-domain keccak-tiny style round constants / rotation (compact Swift port).
    static func hash(_ input: Data) -> Data {
        var state = [UInt64](repeating: 0, count: 25)
        let rate = 136 // 1088 bits for keccak256
        var block = [UInt8](repeating: 0, count: rate)
        var offset = 0
        for byte in input {
            block[offset] ^= byte
            offset += 1
            if offset == rate {
                absorb(&state, block)
                offset = 0
                block = [UInt8](repeating: 0, count: rate)
            }
        }
        block[offset] ^= 0x01
        block[rate - 1] ^= 0x80
        absorb(&state, block)

        var out = [UInt8](repeating: 0, count: 32)
        var produced = 0
        while produced < 32 {
            for i in 0..<rate / 8 {
                let lane = state[i].littleEndian
                withUnsafeBytes(of: lane) { raw in
                    for b in raw {
                        if produced < 32 {
                            out[produced] = b
                            produced += 1
                        }
                    }
                }
            }
            if produced < 32 { keccakF(&state) }
        }
        return Data(out)
    }

    private static func absorb(_ state: inout [UInt64], _ block: [UInt8]) {
        for i in 0..<rate / 8 {
            var lane: UInt64 = 0
            for j in 0..<8 {
                lane |= UInt64(block[i * 8 + j]) << (8 * j)
            }
            state[i] ^= lane
        }
        keccakF(&state)
    }

    private static let rate = 136

    private static let rotc: [Int] = [
        1, 3, 6, 10, 15, 21, 28, 36, 45, 55, 2, 14,
        27, 41, 56, 8, 25, 43, 62, 18, 39, 61, 20, 44
    ]
    private static let piln: [Int] = [
        10, 7, 11, 17, 18, 3, 5, 16, 8, 21, 24, 4,
        15, 23, 19, 13, 12, 2, 20, 14, 22, 9, 6, 1
    ]
    private static let rndc: [UInt64] = [
        0x0000000000000001, 0x0000000000008082, 0x800000000000808a, 0x8000000080008000,
        0x000000000000808b, 0x0000000080000001, 0x8000000080008081, 0x8000000000008009,
        0x000000000000008a, 0x0000000000000088, 0x0000000080008009, 0x000000008000000a,
        0x000000008000808b, 0x800000000000008b, 0x8000000000008089, 0x8000000000008003,
        0x8000000000008002, 0x8000000000000080, 0x000000000000800a, 0x800000008000000a,
        0x8000000080008081, 0x8000000000008080, 0x0000000080000001, 0x8000000080008008
    ]

    private static func rotl64(_ x: UInt64, _ y: Int) -> UInt64 {
        (x << y) | (x >> (64 - y))
    }

    private static func keccakF(_ st: inout [UInt64]) {
        for round in 0..<24 {
            var bc = [UInt64](repeating: 0, count: 5)
            for i in 0..<5 {
                bc[i] = st[i] ^ st[i + 5] ^ st[i + 10] ^ st[i + 15] ^ st[i + 20]
            }
            for i in 0..<5 {
                let t = bc[(i + 4) % 5] ^ rotl64(bc[(i + 1) % 5], 1)
                for j in stride(from: 0, to: 25, by: 5) {
                    st[j + i] ^= t
                }
            }
            var t = st[1]
            for i in 0..<24 {
                let j = piln[i]
                bc[0] = st[j]
                st[j] = rotl64(t, rotc[i])
                t = bc[0]
            }
            for j in stride(from: 0, to: 25, by: 5) {
                for i in 0..<5 { bc[i] = st[j + i] }
                for i in 0..<5 {
                    st[j + i] ^= (~bc[(i + 1) % 5]) & bc[(i + 2) % 5]
                }
            }
            st[0] ^= rndc[round]
        }
    }
}

private extension Data {
    init?(hexString: String) {
        let cleaned = hexString.replacingOccurrences(of: " ", with: "")
        guard cleaned.count % 2 == 0 else { return nil }
        var data = Data()
        var index = cleaned.startIndex
        while index < cleaned.endIndex {
            let next = cleaned.index(index, offsetBy: 2)
            guard let byte = UInt8(cleaned[index..<next], radix: 16) else { return nil }
            data.append(byte)
            index = next
        }
        self = data
    }
}
