import SwiftUI

struct WalletView: View {
    @Environment(LanguageManager.self) private var language
    @Environment(AuthStore.self) private var auth

    let currency: String

    @State private var bills: [WalletBill] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var withdrawAmount = ""
    @State private var withdrawAddress = ""
    @State private var isWithdrawing = false
    @State private var latest: WithdrawLatest?

    var body: some View {
        List {
            Section(language.t("wallet.balance")) {
                Text(auth.balance(for: currency))
                    .font(.largeTitle.bold())
                Text(currency)
                    .foregroundStyle(.secondary)
            }

            if currency.uppercased() == "USDT" || currency.uppercased() == "FEC" {
                Section(language.t("wallet.withdraw")) {
                    TextField(language.t("wallet.amount"), text: $withdrawAmount)
                        .keyboardType(.decimalPad)
                    TextField(language.t("wallet.address"), text: $withdrawAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button {
                        Task { await withdraw() }
                    } label: {
                        if isWithdrawing {
                            ProgressView()
                        } else {
                            Text(language.t("wallet.submitWithdraw"))
                        }
                    }
                    .disabled(isWithdrawing)

                    if let latest {
                        Text("\(language.t("wallet.latest")): \(latest.withdraw_status ?? "-")")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section(language.t("wallet.bills")) {
                if isLoading && bills.isEmpty {
                    ProgressView()
                } else if bills.isEmpty {
                    Text(language.t("wallet.noBills")).foregroundStyle(.secondary)
                } else {
                    ForEach(bills) { bill in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(bill.type ?? "-").font(.subheadline.weight(.semibold))
                                Text(bill.created_at ?? "").font(.caption2).foregroundStyle(.tertiary)
                            }
                            Spacer()
                            Text(bill.amount_str ?? "-")
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                }
            }

            if let errorMessage {
                Section { Text(errorMessage).foregroundStyle(.red) }
            }
        }
        .navigationTitle(currency.uppercased() == "USDT" ? language.t("wallet.usdt") : language.t("wallet.fec"))
        .task { await load() }
        .refreshable { await load() }
    }

    @MainActor
    private func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            try? await auth.refreshUser()
            bills = try await CommerceAPI.bills(currency: currency.uppercased())
            latest = try? await CommerceAPI.withdrawLatest()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func withdraw() async {
        guard let amount = Double(withdrawAmount), amount > 0 else {
            errorMessage = language.t("wallet.requireAmount")
            return
        }
        let address = withdrawAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !address.isEmpty else {
            errorMessage = language.t("wallet.requireAddress")
            return
        }
        isWithdrawing = true
        defer { isWithdrawing = false }
        do {
            try await CommerceAPI.withdraw(amount: amount, address: address, currency: currency.uppercased())
            withdrawAmount = ""
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
