import SwiftUI
import UIKit
import MapKit
import CoreLocation

struct LandmarkDetailView: View {
    private enum SheetTab: String, CaseIterable, Identifiable {
        case product, comment, checkin
        var id: String { rawValue }
    }

    @Environment(LanguageManager.self) private var language
    @Environment(AuthStore.self) private var auth
    @Environment(LocationManager.self) private var location

    let spotId: Int

    @State private var detail: SpotDetailPayload?
    @State private var isLiked = false
    @State private var likeCount = 0
    @State private var isLoading = false
    @State private var isLiking = false
    @State private var errorMessage: String?
    @State private var showLogin = false
    @State private var spotComments: [ProductComment] = []
    @State private var checkins: [CheckinFeedItem] = []
    @State private var sheetTab: SheetTab = .product

    private var isOwner: Bool {
        guard let ownerId = detail?.point?.owner_id else { return false }
        let uid = auth.user?.user_id ?? auth.user?.id
        return uid == ownerId
    }

    private var albumImages: [SpotImage] {
        detail?.point?.images ?? detail?.point_images ?? detail?.images ?? []
    }

    var body: some View {
        Group {
            if isLoading && detail == nil {
                ProgressView(language.t("common.loading"))
            } else if let errorMessage, detail == nil {
                ContentUnavailableView {
                    Label(language.t("common.error"), systemImage: "exclamationmark.triangle")
                } description: {
                    Text(errorMessage)
                } actions: {
                    Button(language.t("common.retry")) { Task { await load() } }
                }
            } else if let point = detail?.point {
                ZStack(alignment: .bottom) {
                    ScrollView {
                        VStack(spacing: 0) {
                            coverHero(point)
                            sheetContent(point)
                                .background(Color.white)
                                .clipShape(UnevenRoundedRectangle(
                                    topLeadingRadius: 16,
                                    bottomLeadingRadius: 0,
                                    bottomTrailingRadius: 0,
                                    topTrailingRadius: 16
                                ))
                                .offset(y: -20)
                                .padding(.bottom, 96)
                        }
                    }

                    checkinFAB(point)
                }
                .background(Color.white)
            }
        }
        .navigationTitle(language.t("landmark.detail"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                if isOwner {
                    NavigationLink {
                        ModifyLandmarkView(spotId: spotId)
                    } label: {
                        Image(systemName: "pencil")
                    }
                    .accessibilityLabel(language.t("landmark.edit"))

                    NavigationLink {
                        CreateProductView(spotId: spotId)
                    } label: {
                        Image(systemName: "plus.rectangle.on.folder")
                    }
                    .accessibilityLabel(language.t("product.create"))
                }
                if let point = detail?.point {
                    NavigationLink {
                        LandmarkLicenseView(
                            point: point,
                            coverURL: point.landmark_image ?? detail?.images?.first?.image_url ?? detail?.point_images?.first?.image_url
                        )
                    } label: {
                        Image(systemName: "person.text.rectangle")
                    }
                    .accessibilityLabel(language.t("license.nav"))
                }
                NavigationLink {
                    LandmarkReportView(spotId: spotId)
                } label: {
                    Image(systemName: "exclamationmark.bubble")
                }
                .accessibilityLabel(language.t("report.title"))
            }
        }
        .task { await load() }
        .sheet(isPresented: $showLogin) {
            NavigationStack { LoginView() }
        }
    }

    // MARK: - Cover

    private func coverHero(_ point: SpotPoint) -> some View {
        ZStack(alignment: .bottomLeading) {
            AsyncImage(url: URL(string: point.landmark_image ?? albumImages.first?.image_url ?? "")) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFill()
                default:
                    Color(red: 0.75, green: 0.78, blue: 0.84)
                }
            }
            .frame(height: 250)
            .frame(maxWidth: .infinity)
            .clipped()

            if !albumImages.isEmpty {
                HStack(spacing: 0) {
                    Text(language.t("landmark.cover"))
                        .font(.system(size: 12, weight: .medium))
                    Text("  |  ")
                        .foregroundStyle(.white.opacity(0.7))
                    NavigationLink {
                        AlbumView(images: albumImages, title: language.t("landmark.album"))
                    } label: {
                        Text(language.t("landmark.album"))
                            .font(.system(size: 12, weight: .medium))
                    }
                    .buttonStyle(.plain)
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(.black.opacity(0.35), in: Capsule())
                .padding(.leading, 12)
                .padding(.bottom, 36)
            }
        }
    }

    // MARK: - Sheet body

    private func sheetContent(_ point: SpotPoint) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            headerRow(point)
            metaRow(point)

            let description = point.description ?? point.description_en ?? point.description_cn ?? ""
            if !description.isEmpty {
                Text(description)
                    .font(.body)
                    .foregroundStyle(Theme.text)
            }

            LandmarkContactsSection(point: point)

            tabBar
            tabBody(point)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func headerRow(_ point: SpotPoint) -> some View {
        HStack(alignment: .top, spacing: 10) {
            AsyncImage(url: URL(string: albumImages.first?.image_url ?? point.landmark_image ?? "")) { phase in
                switch phase {
                case .success(let image): image.resizable().scaledToFill()
                default: Color.gray.opacity(0.15)
                }
            }
            .frame(width: 36, height: 36)
            .clipShape(Circle())

            VStack(alignment: .leading, spacing: 6) {
                Text(point.displayTitle)
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(Theme.text)

                if let category = point.category ?? point.category_en, !category.isEmpty {
                    Text(category)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Theme.text)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(categoryTint(category).opacity(0.35), in: Capsule())
                }
            }

            Spacer(minLength: 8)

            Button {
                Task { await toggleLike() }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: isLiked ? "heart.fill" : "heart")
                    Text("\(likeCount)")
                        .font(.system(size: 12, weight: .medium))
                }
                .foregroundStyle(isLiked ? Color.red : Theme.text)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.black.opacity(0.04), in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(isLiking)
        }
    }

    private func metaRow(_ point: SpotPoint) -> some View {
        HStack(spacing: 16) {
            if let ownerId = point.owner_id, ownerId > 0 {
                NavigationLink {
                    UserHomeView(userId: ownerId)
                } label: {
                    HStack(spacing: 6) {
                        AsyncImage(url: URL(string: point.owner_avatar ?? detail?.owner_avatar ?? "")) { phase in
                            switch phase {
                            case .success(let image): image.resizable().scaledToFill()
                            default: Image("DefaultAvatar").resizable().scaledToFill()
                            }
                        }
                        .frame(width: 22, height: 22)
                        .clipShape(Circle())
                        Text(point.owner_username ?? detail?.owner_username ?? language.t("user.profile"))
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.text)
                            .lineLimit(1)
                    }
                }
                .buttonStyle(.plain)
            }

            Spacer()

            if let distanceText = formattedDistance(to: point) {
                Text(distanceText)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }

            if point.latitude != nil, point.longitude != nil {
                Button {
                    openDirections(to: point)
                } label: {
                    HStack(spacing: 4) {
                        Image("SendIcon")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 18, height: 18)
                        Text(language.t("landmark.navigation"))
                            .font(.system(size: 13))
                    }
                    .foregroundStyle(Theme.text)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var tabBar: some View {
        HStack(spacing: 16) {
            tabButton(.product, title: language.t("landmark.products"))
            tabButton(.comment, title: language.t("landmark.reviews"))
            tabButton(.checkin, title: language.t("mine.myCheckIn"))
            Spacer()
        }
        .padding(.top, 4)
    }

    private func tabButton(_ tab: SheetTab, title: String) -> some View {
        Button {
            sheetTab = tab
        } label: {
            Text(title)
                .font(.system(size: sheetTab == tab ? 16 : 14, weight: .medium))
                .foregroundStyle(sheetTab == tab ? Theme.text : Theme.text.opacity(0.45))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func tabBody(_ point: SpotPoint) -> some View {
        switch sheetTab {
        case .product:
            productsTab
        case .comment:
            commentsTab
        case .checkin:
            checkinsTab
        }
    }

    private var productsTab: some View {
        let products = detail?.product ?? []
        return Group {
            if products.isEmpty {
                emptyTabText(language.t("landmark.noProduct"))
            } else {
                LazyVGrid(columns: [
                    GridItem(.flexible(), spacing: 8),
                    GridItem(.flexible(), spacing: 8)
                ], spacing: 8) {
                    ForEach(products) { product in
                        NavigationLink {
                            ProductDetailView(productId: product.id)
                        } label: {
                            productCard(product)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func productCard(_ product: ShopProduct) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            AsyncImage(url: URL(string: product.cover ?? "")) { phase in
                switch phase {
                case .success(let image): image.resizable().scaledToFill()
                default: Color.gray.opacity(0.1)
                }
            }
            .frame(height: 110)
            .frame(maxWidth: .infinity)
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: 8))

            Text(product.name ?? "")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.text)
                .lineLimit(2)
            Text(product.displayPrice)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.brand)
        }
        .padding(6)
        .background(Color.black.opacity(0.02), in: RoundedRectangle(cornerRadius: 10))
    }

    private var commentsTab: some View {
        Group {
            if spotComments.isEmpty {
                emptyTabText(language.t("landmark.noComment"))
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(spotComments) { comment in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(comment.user?.nickname ?? "User")
                                    .font(.subheadline.weight(.semibold))
                                Spacer()
                                if let star = comment.star {
                                    Text(String(repeating: "★", count: max(0, min(5, star))))
                                        .font(.caption)
                                        .foregroundStyle(.orange)
                                }
                            }
                            Text(comment.content ?? "")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    private var checkinsTab: some View {
        Group {
            if checkins.isEmpty {
                emptyTabText(language.t("checkin.feedEmpty"))
            } else {
                VStack(spacing: 0) {
                    ForEach(checkins) { item in
                        if let id = item.checkin?.id {
                            NavigationLink {
                                CheckinDetailView(checkinId: id)
                            } label: {
                                CheckinFeedRow(item: item)
                                    .padding(.vertical, 8)
                            }
                            .buttonStyle(.plain)
                            Divider()
                        }
                    }
                    NavigationLink {
                        CheckinFeedView(spotId: spotId)
                    } label: {
                        Text(language.t("common.loadMore"))
                            .font(.caption)
                            .foregroundStyle(Theme.link)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }
                }
            }
        }
    }

    private func emptyTabText(_ text: String) -> some View {
        Text("--- \(text) ---")
            .font(.system(size: 14))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)
    }

    // MARK: - FAB

    private func checkinFAB(_ point: SpotPoint) -> some View {
        Group {
            if auth.isLoggedIn {
                NavigationLink {
                    CreateCheckinView(spotId: spotId, spotTitle: point.title ?? point.displayTitle)
                } label: {
                    Image("MapCheckin")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 72, height: 72)
                        .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
                }
            } else {
                Button { showLogin = true } label: {
                    Image("MapCheckin")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 72, height: 72)
                        .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.bottom, 12)
    }

    // MARK: - Data

    @MainActor
    private func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let payload = try await SpotAPI.detail(spotId: spotId)
            detail = payload
            isLiked = payload.liked ?? payload.point?.liked ?? false
            likeCount = payload.point?.like_count ?? 0
            async let commentsTask = SpotAPI.comments(spotId: spotId)
            async let checkinsTask = CheckinAPI.spotLatest(spotId: spotId, page: 1)
            spotComments = (try? await commentsTask) ?? []
            checkins = (try? await checkinsTask) ?? []
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func toggleLike() async {
        guard auth.isLoggedIn else {
            showLogin = true
            return
        }
        isLiking = true
        defer { isLiking = false }
        do {
            try await SpotAPI.like(spotId: spotId)
            isLiked.toggle()
            likeCount = max(0, likeCount + (isLiked ? 1 : -1))
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func openDirections(to point: SpotPoint) {
        guard let lat = point.latitude, let lon = point.longitude else { return }
        let coordinate = CLLocationCoordinate2D(latitude: lat, longitude: lon)
        let placemark = MKPlacemark(coordinate: coordinate)
        let item = MKMapItem(placemark: placemark)
        item.name = point.title ?? point.title_en ?? point.location
        item.openInMaps(launchOptions: [
            MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving
        ])
    }

    private func formattedDistance(to point: SpotPoint) -> String? {
        if let apiDistance = detail?.distance ?? point.distance {
            return formatMeters(apiDistance)
        }
        guard let lat = point.latitude,
              let lon = point.longitude,
              let user = location.coordinate else { return nil }
        let meters = CLLocation(latitude: user.latitude, longitude: user.longitude)
            .distance(from: CLLocation(latitude: lat, longitude: lon))
        return formatMeters(meters)
    }

    private func formatMeters(_ meters: Double) -> String {
        if meters < 1000 { return String(format: "%.0fm", meters) }
        return String(format: "%.1fkm", meters / 1000)
    }

    private func categoryTint(_ category: String) -> Color {
        switch category.lowercased() {
        case "business", "商业": return Color(red: 0.45, green: 1.0, blue: 0.81)
        case "shopping", "购物": return Color(red: 0.96, green: 0.63, blue: 1.0)
        case "sports", "体育运动": return Color(red: 0.0, green: 0.48, blue: 1.0)
        default: return Theme.brand
        }
    }
}

private struct LandmarkContactsSection: View {
    @Environment(LanguageManager.self) private var language
    let point: SpotPoint
    @State private var openingMessage: String?

    var body: some View {
        let rows = contactRows
        if !rows.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(rows, id: \.title) { row in
                        Button {
                            Task { await open(row) }
                        } label: {
                            Label(row.title, systemImage: row.icon)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(Theme.text)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(Color.black.opacity(0.04), in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            if let openingMessage {
                Text(openingMessage)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var contactRows: [(title: String, icon: String, value: String, kind: String)] {
        var rows: [(String, String, String, String)] = []
        if let v = point.telegram_url, !v.isEmpty { rows.append((language.t("contact.telegram"), "paperplane", v, "url")) }
        if let v = point.whatsapp_url, !v.isEmpty { rows.append((language.t("contact.whatsapp"), "phone", v, "url")) }
        if let v = point.wechat, !v.isEmpty { rows.append((language.t("contact.wechat"), "message", v, "copy")) }
        if let v = point.pcn_url, !v.isEmpty { rows.append((language.t("contact.pcn"), "link", v, "url")) }
        if let v = point.believe_url, !v.isEmpty {
            rows.append((language.t("contact.believe"), "person.crop.circle", v, "url"))
        } else if let id = point.believe_id, !id.isEmpty {
            rows.append((language.t("contact.believe"), "person.crop.circle", id, "believe"))
        }
        if let v = point.external_url, !v.isEmpty { rows.append((language.t("contact.website"), "globe", v, "url")) }
        return rows
    }

    @MainActor
    private func open(_ row: (title: String, icon: String, value: String, kind: String)) async {
        openingMessage = nil
        switch row.kind {
        case "copy":
            UIPasteboard.general.string = row.value
            openingMessage = language.t("common.copied")
        case "believe":
            if let link = try? await SystemAPI.believeChatLink(believeId: row.value),
               let url = URL(string: link) {
                await UIApplication.shared.open(url)
            } else {
                openingMessage = language.t("contact.believeFailed")
            }
        default:
            let raw = row.value.hasPrefix("http") ? row.value : "https://\(row.value)"
            if let url = URL(string: raw) {
                await UIApplication.shared.open(url)
            }
        }
    }
}
