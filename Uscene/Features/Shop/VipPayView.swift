import SwiftUI

struct VipPayView: View {
    @Environment(LanguageManager.self) private var language
    @Environment(AuthStore.self) private var auth
    @Environment(\.dismiss) private var dismiss

    @State private var plans: [MemberPlan] = []
    @State private var memberInfo: MemberInfo?
    @State private var selectedPlanId: Int?
    @State private var currency: VipCurrency = .usdt
    @State private var isLoading = false
    @State private var isBuying = false
    @State private var errorMessage: String?
    @State private var createdOrderId: Int?
    @State private var showLogin = false
    @State private var showCurrencyPicker = false

    private enum VipCurrency: String, CaseIterable {
        case usdt = "USDT"
        case fec = "FEC"

        var payType: String {
            switch self {
            case .usdt: return "ETH"
            case .fec: return "FEC"
            }
        }
    }

    private var selectedPlan: MemberPlan? {
        plans.first { $0.id == selectedPlanId } ?? plans.first
    }

    private var isVip: Bool { memberInfo?.is_vip == true }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                heroHeader
                benefitRow
                    .padding(.horizontal, 16)
                    .padding(.top, 16)

                planSection
                    .padding(.horizontal, 16)
                    .padding(.top, 20)

                benefitDetail
                    .padding(.horizontal, 16)
                    .padding(.top, 20)

                currencyRow
                    .padding(.horizontal, 16)
                    .padding(.top, 16)

                if let errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                }

                Color.clear.frame(height: 100)
            }
        }
        .background(Color(red: 0.945, green: 0.945, blue: 1))
        .safeAreaInset(edge: .bottom) {
            buyBar
        }
        .navigationTitle(language.t("vip.title"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink {
                    VipOrdersView()
                } label: {
                    Image(systemName: "list.bullet.rectangle")
                }
            }
        }
        .navigationDestination(item: $createdOrderId) { orderId in
            OrderDetailView(orderId: orderId, kind: .member)
        }
        .sheet(isPresented: $showLogin) { NavigationStack { LoginView() } }
        .confirmationDialog(language.t("vip.currency"), isPresented: $showCurrencyPicker, titleVisibility: .visible) {
            ForEach(VipCurrency.allCases, id: \.self) { item in
                Button(item.rawValue) { currency = item }
            }
            Button(language.t("common.cancel"), role: .cancel) {}
        }
        .task { await load() }
        .refreshable { await load() }
    }

    private var heroHeader: some View {
        ZStack(alignment: .bottom) {
            Image("BuyVipBg")
                .resizable()
                .scaledToFill()
                .frame(height: 210)
                .frame(maxWidth: .infinity)
                .clipped()

            LinearGradient(
                colors: [Color(red: 0.42, green: 0.41, blue: 1).opacity(0.2), Color(red: 0.945, green: 0.945, blue: 1)],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 210)

            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 10) {
                        AsyncImage(url: URL(string: auth.user?.avatar_url ?? "")) { phase in
                            switch phase {
                            case .success(let image): image.resizable().scaledToFill()
                            default: Image("DefaultAvatar").resizable().scaledToFill()
                            }
                        }
                        .frame(width: 48, height: 48)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(Color.white, lineWidth: 2))

                        VStack(alignment: .leading, spacing: 4) {
                            Text(auth.isLoggedIn ? (auth.user?.nickname ?? "Uscene") : language.t("login.pleaseLogin"))
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(.white)
                            Text(isVip
                                  ? (memberInfo?.expireText ?? language.t("vip.active"))
                                  : language.t("vip.inactive"))
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.9))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Color.white.opacity(0.2), in: Capsule())
                        }
                    }
                }
                Spacer()
                Image("BuyVipHero")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 110, height: 110)
                    .padding(.trailing, 8)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 18)
        }
    }

    private var benefitRow: some View {
        HStack(spacing: 8) {
            benefitCell(asset: "VipInfo1", title: language.t("vip.info1"))
            benefitCell(asset: "VipInfo2", title: language.t("vip.info2"))
            benefitCell(asset: "VipInfo3", title: language.t("vip.info3"))
        }
    }

    private func benefitCell(asset: String, title: String) -> some View {
        VStack(spacing: 8) {
            Image(asset)
                .resizable()
                .scaledToFit()
                .frame(width: 36, height: 36)
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.text)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 12))
    }

    private var planSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(language.t("vip.plans"))
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Theme.text)

            if isLoading && plans.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding()
            } else {
                ForEach(plans) { plan in
                    Button {
                        selectedPlanId = plan.id
                    } label: {
                        planCard(plan)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func planCard(_ plan: MemberPlan) -> some View {
        let selected = plan.id == selectedPlan?.id
        let price = currency == .usdt ? (plan.usdt_price ?? 0) : (plan.fec_price ?? 0)
        let origin = currency == .usdt ? plan.usdt_origin_price : plan.fec_origin_price

        return HStack {
            VStack(alignment: .leading, spacing: 6) {
                Text(plan.periodText)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.text)
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(String(format: "%@ %.2f", currency.rawValue, price))
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(Color(red: 0.42, green: 0.41, blue: 1))
                    if let origin, origin > price {
                        Text(String(format: "%.2f", origin))
                            .font(.caption)
                            .strikethrough()
                            .foregroundStyle(.secondary)
                    }
                }
            }
            Spacer()
            Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 22))
                .foregroundStyle(selected ? Color(red: 0.42, green: 0.41, blue: 1) : .secondary)
        }
        .padding(16)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(selected ? Color(red: 0.42, green: 0.41, blue: 1) : Color.clear, lineWidth: 2)
        )
    }

    private var benefitDetail: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(language.t("vip.infoDescTitle"))
                .font(.system(size: 16, weight: .semibold))
            Text(language.t("vip.desc1")).font(.subheadline).foregroundStyle(.secondary)
            Text(language.t("vip.desc2")).font(.subheadline).foregroundStyle(.secondary)
            Text(language.t("vip.desc3")).font(.subheadline).foregroundStyle(.secondary)
            Text(language.t("vip.infoDesc"))
                .font(.caption)
                .foregroundStyle(.tertiary)
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 12))
    }

    private var currencyRow: some View {
        Button { showCurrencyPicker = true } label: {
            HStack {
                Text(language.t("vip.currency"))
                    .foregroundStyle(Theme.text)
                Spacer()
                Text(currency.rawValue)
                    .foregroundStyle(Color(red: 0.42, green: 0.41, blue: 1))
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(16)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }

    private var buyBar: some View {
        let price = currency == .usdt
            ? (selectedPlan?.usdt_price ?? 0)
            : (selectedPlan?.fec_price ?? 0)

        return HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(language.t("vip.total"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(String(format: "%@ %.2f", currency.rawValue, price))
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(Color(red: 0.42, green: 0.41, blue: 1))
            }
            Spacer()
            Button {
                guard let plan = selectedPlan else { return }
                Task { await buy(plan) }
            } label: {
                Text(auth.isLoggedIn ? language.t("shop.buy") : language.t("login.signIn"))
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 28)
                    .padding(.vertical, 12)
                    .background(Color(red: 0.42, green: 0.41, blue: 1), in: Capsule())
            }
            .disabled(isBuying || selectedPlan == nil)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
    }

    @MainActor
    private func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            plans = try await CommerceAPI.memberConfig()
            if selectedPlanId == nil {
                selectedPlanId = plans.first?.id
            }
            if auth.isLoggedIn {
                memberInfo = try? await CommerceAPI.memberInfo()
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func buy(_ plan: MemberPlan) async {
        guard auth.isLoggedIn else {
            showLogin = true
            return
        }
        isBuying = true
        defer { isBuying = false }
        do {
            let order = try await CommerceAPI.createMemberOrder(memberId: plan.id, payType: currency.payType)
            let oid = order.resolvedId
            if oid > 0 {
                createdOrderId = oid
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct VipOrdersView: View {
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
                ContentUnavailableView(language.t("order.empty"), systemImage: "crown")
            } else {
                List(items) { order in
                    if order.resolvedId > 0 {
                        NavigationLink {
                            OrderDetailView(orderId: order.resolvedId, kind: .member)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(order.period.map { "\($0) days" } ?? "VIP")
                                    .font(.headline)
                                Text(order.displayAmount)
                                    .font(.subheadline)
                                    .foregroundStyle(Color.accentColor)
                                Text(order.status ?? "-")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
            }
        }
        .navigationTitle(language.t("vip.orders"))
        .task { await load() }
        .refreshable { await load() }
    }

    @MainActor
    private func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            items = try await CommerceAPI.memberOrders()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
