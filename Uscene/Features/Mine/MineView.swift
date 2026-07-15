import SwiftUI
import UIKit

struct MineView: View {
    @Environment(LanguageManager.self) private var language
    @Environment(AuthStore.self) private var auth

    var unreadCount: Int = 0
    @State private var showLogin = false
    @State private var stats: UserStatistics?
    @State private var invite: InviteInfo?
    @State private var premium: PremiumInfo?
    @State private var segment: MineSegment = .profile
    @State private var myCheckins: [CheckinFeedItem] = []

    private enum MineSegment {
        case profile, checkins
    }

    private let gridColumns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 4)

    var body: some View {
        ScrollView {
            ZStack(alignment: .top) {
                Image("MineBG")
                    .resizable()
                    .scaledToFill()
                    .frame(height: 330)
                    .frame(maxWidth: .infinity)
                    .clipped()

                VStack(spacing: 0) {
                    headerBar
                        .tabRootHeaderInset(8)

                    profileHeader
                        .padding(.top, 8)

                    socialRow
                        .padding(.horizontal, 16)
                        .padding(.top, 8)

                    vipBanner
                        .padding(.horizontal, 16)
                        .padding(.top, 12)
                        .padding(.bottom, 16)

                    segmentTabs

                    Group {
                        if segment == .profile {
                            profileContent
                        } else {
                            checkinsContent
                        }
                    }
                    .background(Color.white)
                }
            }
        }
        .background(Color(red: 0.973, green: 0.973, blue: 0.973))
        .tabRootChrome()
        .sheet(isPresented: $showLogin) {
            NavigationStack { LoginView() }
        }
        .refreshable { await refreshExtras() }
        .task { await refreshExtras() }
    }

    private var headerBar: some View {
        HStack {
            Spacer()
            NavigationLink {
                SettingsView()
            } label: {
                Image("SettingBlack")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 18, height: 18)
                    .frame(width: 36, height: 36)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .frame(height: 44)
    }

    private var profileHeader: some View {
        Group {
            if auth.isLoggedIn {
                VStack(spacing: 8) {
                    NavigationLink {
                        ProfileEditView()
                    } label: {
                        HStack(spacing: 12) {
                            AsyncImage(url: URL(string: auth.user?.avatar_url ?? "")) { phase in
                                switch phase {
                                case .success(let image):
                                    image.resizable().scaledToFill()
                                default:
                                    Image("DefaultAvatar").resizable().scaledToFill()
                                }
                            }
                            .frame(width: 72, height: 72)
                            .clipShape(Circle())
                            .overlay(Circle().stroke(Color.white, lineWidth: 2))

                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 8) {
                                    Text(auth.user?.nickname ?? "Uscene")
                                        .font(.system(size: 20, weight: .semibold))
                                        .foregroundStyle(Theme.text)
                                    if let level = auth.user?.level {
                                        Text("Lv.\(level)")
                                            .font(.caption2.weight(.bold))
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(Theme.brand.opacity(0.15), in: Capsule())
                                            .foregroundStyle(Theme.brand)
                                    }
                                }
                                if let code = invite?.resolvedCode ?? auth.user?.invite_code, !code.isEmpty {
                                    Text("ID: \(code)")
                                        .font(.system(size: 12))
                                        .foregroundStyle(Theme.text.opacity(0.7))
                                }
                            }
                            Spacer()
                        }
                        .padding(.horizontal, 16)
                    }
                    .buttonStyle(.plain)

                    Text(auth.user?.profileDescription?.isEmpty == false
                          ? (auth.user?.profileDescription ?? "")
                          : language.t("mine.writeSomething"))
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.text)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 16)
                }
            } else {
                Button { showLogin = true } label: {
                    HStack(spacing: 12) {
                        Image("DefaultAvatar")
                            .resizable()
                            .frame(width: 72, height: 72)
                            .clipShape(Circle())
                        VStack(alignment: .leading, spacing: 4) {
                            Text(language.t("login.pleaseLogin"))
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundStyle(Theme.text)
                            Text(language.t("login.signIn"))
                                .font(.system(size: 12))
                                .foregroundStyle(Theme.text.opacity(0.6))
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var socialRow: some View {
        HStack(spacing: 16) {
            socialStat(value: auth.userStat?.followers_count ?? 0, title: language.t("mine.fans"))
            socialStat(value: auth.userStat?.following_count ?? 0, title: language.t("mine.followers"))
            socialStat(value: auth.userStat?.likes_count ?? 0, title: language.t("mine.like"))
            Spacer()
        }
        .padding(.vertical, 8)
    }

    private func socialStat(value: Int, title: String) -> some View {
        HStack(spacing: 6) {
            Text("\(value)")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Theme.text)
            Text(title)
                .font(.system(size: 12))
                .foregroundStyle(Theme.text.opacity(0.6))
        }
    }

    private var vipBanner: some View {
        HStack {
            VStack(alignment: .leading, spacing: 8) {
                Text(premium?.is_vip == true || premium?.is_premium == true
                      ? language.t("mine.vipInfo")
                      : language.t("mine.buyVipTitle"))
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(
                        (premium?.is_vip == true || premium?.is_premium == true)
                        ? Color(red: 1, green: 0.365, blue: 0)
                        : Theme.shop
                    )
                Text(premium?.is_vip == true || premium?.is_premium == true
                      ? (premium?.expired_at ?? language.t("vip.active"))
                      : language.t("mine.buyVipDesc"))
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.text)
                    .lineLimit(2)
            }
            Spacer()
            NavigationLink {
                VipPayView()
            } label: {
                Text(premium?.is_vip == true || premium?.is_premium == true
                      ? language.t("mine.buyVipAgain")
                      : language.t("mine.buyVip"))
                    .font(.system(size: 14))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(
                        (premium?.is_vip == true || premium?.is_premium == true)
                        ? Color(red: 1, green: 0.365, blue: 0)
                        : Theme.shop,
                        in: Capsule()
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 10))
    }

    private var segmentTabs: some View {
        HStack(spacing: 8) {
            segmentButton(.profile, title: language.t("mine.userInfo"))
            segmentButton(.checkins, title: language.t("mine.myCheckIn"))
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color.white)
        .clipShape(UnevenRoundedRectangle(topLeadingRadius: 20, topTrailingRadius: 20))
    }

    private func segmentButton(_ value: MineSegment, title: String) -> some View {
        Button {
            segment = value
        } label: {
            VStack(spacing: 4) {
                Text(title)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(segment == value ? Theme.text : Theme.text.opacity(0.6))
                Capsule()
                    .fill(segment == value ? Theme.link : Color.clear)
                    .frame(width: 36, height: 3)
            }
            .padding(8)
        }
        .buttonStyle(.plain)
    }

    private var profileContent: some View {
        VStack(spacing: 0) {
            walletBlock
            dividerBand
            commerceGrid
            dividerBand
            moreLinks
            if auth.isLoggedIn {
                Button(role: .destructive) {
                    auth.logout()
                } label: {
                    Text(language.t("login.logout"))
                        .frame(maxWidth: .infinity)
                        .padding()
                }
                .padding(.top, 8)
                .padding(.bottom, 40)
            } else {
                Color.clear.frame(height: 40)
            }
        }
    }

    private var walletBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(language.t("mine.walletAmount"))
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.text.opacity(0.6))

            NavigationLink {
                WalletView(currency: "FEC")
            } label: {
                walletRow(badge: "FEC")
            }
            .buttonStyle(.plain)

            Divider().overlay(Color(red: 0.933, green: 0.941, blue: 0.961))

            NavigationLink {
                WalletView(currency: "USDT")
            } label: {
                walletRow(badge: "USDT")
            }
            .buttonStyle(.plain)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func walletRow(badge: String) -> some View {
        HStack {
            HStack(spacing: 8) {
                Text(badge)
                    .font(.system(size: 8, weight: .medium))
                    .foregroundStyle(.white)
                    .frame(width: 20, height: 20)
                    .background(Theme.shop, in: Circle())
                Text(badge)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.text)
            }
            Spacer()
            Text(auth.balance(for: badge))
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(Theme.text)
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 8)
    }

    private var commerceGrid: some View {
        LazyVGrid(columns: gridColumns, spacing: 20) {
            MineGridItem(title: language.t("order.myBuy"), systemImage: "bag") { MyBuyOrdersView() }
            MineGridItem(title: language.t("order.mySell"), systemImage: "shippingbox") { MySellOrdersView() }
            MineGridItem(title: language.t("product.myList"), asset: "IconProduct") { MyProductsView() }
            MineGridItem(title: language.t("comment.title"), systemImage: "star") { MyCommentsView() }
            MineGridItem(title: language.t("codes.title"), systemImage: "qrcode") { MyVerificationCodesView() }
            MineGridItem(title: language.t("order.myCodes"), systemImage: "ticket") { MyCodeOrdersView() }
            MineGridItem(title: language.t("product.favorites"), systemImage: "heart") { ProductFavoritesView() }
            MineGridItem(title: language.t("product.history"), systemImage: "clock") { ProductHistoryView() }
            MineGridItem(title: language.t("address.title"), systemImage: "mappin.circle") { MyAddressView() }
            MineGridItem(title: language.t("landmark.myList"), systemImage: "mappin.and.ellipse") { MyLandmarksView() }
            MineGridItem(title: language.t("collection.title"), systemImage: "heart.circle") { CollectionView() }
            MineGridItem(title: language.t("messages.title"), systemImage: "bell", badge: unreadCount) { MessagesView() }
            MineGridItem(title: language.t("ads.title"), systemImage: "gift") { AdsRewardsView() }
        }
        .padding(16)
    }

    private var moreLinks: some View {
        VStack(spacing: 0) {
            NavigationLink {
                MyVerificationCodesView()
            } label: {
                linkRow(title: language.t("mine.myCodes"), value: "\(stats?.total_verify_code ?? 0)")
            }
            Divider().padding(.leading, 16)
            NavigationLink {
                MyCodeOrdersView()
            } label: {
                linkRow(title: language.t("mine.myOrders"), value: "\(stats?.total_verify_code_order ?? 0)")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private func linkRow(title: String, value: String) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 12))
                .foregroundStyle(Theme.text)
            Spacer()
            Text(value)
                .font(.system(size: 12))
                .foregroundStyle(Theme.text)
            Image(systemName: "chevron.right")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 12)
    }

    private var checkinsContent: some View {
        Group {
            if !auth.isLoggedIn {
                Button { showLogin = true } label: {
                    Text(language.t("login.pleaseLogin"))
                        .padding()
                }
            } else if myCheckins.isEmpty {
                Text(language.t("checkin.feedEmpty"))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
            } else {
                LazyVStack(spacing: 12) {
                    ForEach(myCheckins) { item in
                        NavigationLink {
                            CheckinDetailView(checkinId: item.checkin?.id ?? item.id)
                        } label: {
                            MineCheckinRow(item: item)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(16)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 200, alignment: .top)
        .padding(.bottom, 40)
    }

    private var dividerBand: some View {
        Color(red: 0.969, green: 0.973, blue: 0.98)
            .frame(height: 8)
    }

    @MainActor
    private func refreshExtras() async {
        guard auth.isLoggedIn else {
            stats = nil
            invite = nil
            premium = nil
            myCheckins = []
            return
        }
        try? await auth.refreshUser()
        async let statsTask = UserAPI.statistics()
        async let inviteTask = UserAPI.inviteInfo()
        async let premiumTask = UserAPI.premiumInfo()
        async let memberTask = CommerceAPI.memberInfo()
        stats = try? await statsTask
        invite = try? await inviteTask
        premium = try? await premiumTask
        if let member = try? await memberTask, member.is_vip == true {
            // Prefer member expire text when premium info is empty.
            if premium?.expired_at == nil, let expire = member.expireText {
                premium = PremiumInfo(is_premium: true, is_vip: true, expired_at: expire, level: premium?.level)
            } else if premium == nil {
                premium = PremiumInfo(is_premium: true, is_vip: true, expired_at: member.expireText, level: nil)
            }
        }

        if let userId = auth.user?.user_id ?? auth.user?.id {
            myCheckins = (try? await UserAPI.checkins(userId: userId)) ?? []
        }
    }
}

private struct MineGridItem<Destination: View>: View {
    let title: String
    var systemImage: String?
    var asset: String?
    var badge: Int = 0
    @ViewBuilder let destination: () -> Destination

    var body: some View {
        NavigationLink {
            destination()
        } label: {
            VStack(spacing: 8) {
                ZStack(alignment: .topTrailing) {
                    Group {
                        if let asset {
                            Image(asset).resizable().scaledToFit().frame(width: 28, height: 28)
                        } else if let systemImage {
                            Image(systemName: systemImage)
                                .font(.system(size: 22))
                                .foregroundStyle(Theme.text)
                                .frame(width: 28, height: 28)
                        }
                    }
                    if badge > 0 {
                        Text("\(min(badge, 99))")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 4)
                            .background(Color.red, in: Capsule())
                            .offset(x: 8, y: -6)
                    }
                }
                Text(title)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }
}

private struct MineCheckinRow: View {
    let item: CheckinFeedItem

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            AsyncImage(url: URL(string: item.user?.avatar_url ?? item.checkin?.user?.avatar_url ?? "")) { phase in
                switch phase {
                case .success(let image): image.resizable().scaledToFill()
                default: Image("DefaultAvatar").resizable()
                }
            }
            .frame(width: 44, height: 44)
            .clipShape(Circle())

            VStack(alignment: .leading, spacing: 6) {
                Text(item.user?.nickname ?? item.checkin?.user?.nickname ?? "User")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.text)
                Text(item.checkin?.content ?? "")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                if let title = item.point?.title {
                    Label(title, systemImage: "mappin")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
    }
}
