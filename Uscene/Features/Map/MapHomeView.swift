import SwiftUI
import MapKit

struct MapHomeView: View {
    @Environment(LanguageManager.self) private var language
    @Environment(LocationManager.self) private var location
    @Environment(AuthStore.self) private var auth

    private static let fallbackCoordinate = CLLocationCoordinate2D(latitude: 22.2987, longitude: 114.1723)
    private static let defaultSpan = MKCoordinateSpan(latitudeDelta: 0.04, longitudeDelta: 0.04)

    @State private var position: MapCameraPosition = .region(
        MKCoordinateRegion(center: fallbackCoordinate, span: defaultSpan)
    )
    @State private var spots: [SpotAnnotationItem] = []
    @State private var selected: SpotAnnotationItem?
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var visibleRegion: MKCoordinateRegion?
    @State private var showLogin = false
    @State private var messageUnread = 0
    @State private var didCenterOnUser = false
    /// Bumps when a newer map/check-in load is scheduled; stale responses are ignored (no URLSession cancel).
    @State private var spotsFetchID = 0
    @State private var checkinsFetchID = 0

    @State private var sheetExpanded = false
    @State private var sheetDragOffset: CGFloat = 0
    @State private var checkins: [CheckinFeedItem] = []
    @State private var sheetLoading = false
    @State private var sheetLoadingMore = false
    @State private var sheetCanLoadMore = true
    @State private var topicId = 0
    @State private var tags: [CheckinTag] = []
    @State private var checkinPage = 1
    @State private var recommendCity = ""
    @State private var geocodeFetchID = 0

    private let sheetCollapsed: CGFloat = Theme.mapSheetCollapsed
    private static let sheetSpring = Animation.interactiveSpring(response: 0.38, dampingFraction: 0.86)
    private static let checkinPageSize = 20

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .bottom) {
                mapLayer
                    .ignoresSafeArea(edges: .top)

                mapHeader
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .opacity(sheetExpanded ? 0 : 1)
                    .allowsHitTesting(!sheetExpanded)

                if isLoading {
                    Text(language.t("map.loading"))
                        .font(.caption)
                        .padding(8)
                        .background(.ultraThinMaterial, in: Capsule())
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                        .padding(.top, Theme.topSafeAreaInset + 52)
                        .opacity(sheetExpanded ? 0 : 1)
                } else if let errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .padding(8)
                        .background(.ultraThinMaterial, in: Capsule())
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                        .padding(.top, Theme.topSafeAreaInset + 52)
                        .opacity(sheetExpanded ? 0 : 1)
                }

                mapFABStack
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .padding(.trailing, 10)
                    .padding(.top, Theme.topSafeAreaInset + 20)
                    .opacity(sheetExpanded ? 0 : 1)
                    .allowsHitTesting(!sheetExpanded)

                mapSideStack
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    .padding(.trailing, 10)
                    .padding(.bottom, (sheetExpanded ? geo.size.height : sheetCollapsed) + 70)
                    .opacity(sheetExpanded ? 0 : 1)
                    .allowsHitTesting(!sheetExpanded)

                checkinCTA
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    .padding(.bottom, (sheetExpanded ? geo.size.height : sheetCollapsed) + 8 - sheetDragOffset)
                    .opacity(sheetExpanded ? 0 : 1)
                    .allowsHitTesting(!sheetExpanded)
                    .zIndex(5)
            }
        }
        .overlay(alignment: .bottom) {
            let expandedHeight = Theme.windowHeight
            let sheetHeight = (sheetExpanded ? expandedHeight : sheetCollapsed) - sheetDragOffset
            let clampedSheet = min(max(sheetHeight, sheetCollapsed - 40), expandedHeight)

            mapBottomSheet(height: clampedSheet, expandedHeight: expandedHeight)
                .frame(height: clampedSheet)
                .frame(maxWidth: .infinity, maxHeight: sheetExpanded ? .infinity : clampedSheet, alignment: .bottom)
                .ignoresSafeArea(sheetExpanded ? .container : [], edges: sheetExpanded ? .all : [])
                .animation(Self.sheetSpring, value: sheetExpanded)
        }
        .preference(key: HidesRootTabBarKey.self, value: sheetExpanded)
        .tabRootChrome()
        .sheet(isPresented: $showLogin) {
            NavigationStack { LoginView() }
        }
        .task {
            location.requestPermissionAndLocate()
            tags = (try? await CheckinAPI.tags()) ?? []
            let initial = MKCoordinateRegion(center: Self.fallbackCoordinate, span: Self.defaultSpan)
            visibleRegion = initial
            scheduleFetch(for: initial, debounceMs: 0)
            scheduleCheckins(debounceMs: 0)
            scheduleRecommendCity(for: initial.center, debounceMs: 0)
            await bootstrapAroundUser()
            if auth.isLoggedIn {
                messageUnread = (try? await MessageAPI.unreadCount()) ?? 0
            }
        }
        .onChange(of: location.coordinate?.latitude) { _, _ in
            guard !didCenterOnUser, let coordinate = location.coordinate else { return }
            applyUserLocation(coordinate, animated: true)
        }
        .onChange(of: topicId) { _, _ in
            scheduleCheckins(debounceMs: 200)
        }
        .onChange(of: selected) { _, item in
            if item != nil {
                withAnimation(Self.sheetSpring) {
                    sheetExpanded = false
                }
            }
        }
    }

    // MARK: - Map

    private var mapLayer: some View {
        Map(position: $position, selection: $selected) {
            UserAnnotation()
            ForEach(spots) { item in
                Annotation(item.spot.title ?? "", coordinate: item.coordinate, anchor: .bottom) {
                    MapSpotMarkerView(
                        spot: item.spot,
                        selected: selected?.id == item.id
                    )
                }
                .tag(item)
            }
        }
        .mapStyle(.standard(elevation: .realistic))
        .onMapCameraChange(frequency: .onEnd) { context in
            let region = context.region
            // Ignore tiny camera jitter / echo after programmatic recenter.
            if let previous = visibleRegion,
               abs(previous.center.latitude - region.center.latitude) < 0.0008,
               abs(previous.center.longitude - region.center.longitude) < 0.0008,
               abs(previous.span.latitudeDelta - region.span.latitudeDelta) < 0.002 {
                visibleRegion = region
                return
            }
            visibleRegion = region
            scheduleFetch(for: region, debounceMs: 400)
            scheduleCheckins(debounceMs: 400)
            scheduleRecommendCity(for: region.center, debounceMs: 500)
        }
    }

    private var mapHeader: some View {
        // Match RN MapHeader: height = 44 + safeTop, title sits in the 44pt row below the status bar.
        Text(language.t("home.checkinPlaza"))
            .font(.system(size: 20, weight: .medium))
            .foregroundStyle(Theme.text)
            .frame(height: 44)
            .frame(maxWidth: .infinity)
            .padding(.top, Theme.topSafeAreaInset)
            .background(alignment: .top) {
                LinearGradient(
                    colors: [Color.white.opacity(0.92), Color.white.opacity(0)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: Theme.topSafeAreaInset + 54)
                .frame(maxWidth: .infinity)
                .allowsHitTesting(false)
            }
    }

    private var mapFABStack: some View {
        VStack(spacing: 16) {
            fabCircle {
                if auth.isLoggedIn {
                    NavigationLink {
                        CheckinFeedView()
                    } label: {
                        Image("MapUserBtn").resizable().scaledToFit().frame(width: 14, height: 16)
                    }
                } else {
                    Button { showLogin = true } label: {
                        Image("MapUserBtn").resizable().scaledToFit().frame(width: 14, height: 16)
                    }
                }
            }

            fabCircle {
                NavigationLink {
                    MessagesView()
                } label: {
                    ZStack(alignment: .topTrailing) {
                        Image("MapMessage").resizable().scaledToFit().frame(width: 16, height: 16)
                        if messageUnread > 0 {
                            Text("\(min(messageUnread, 99))")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(minWidth: 16, minHeight: 16)
                                .background(Color.red, in: Circle())
                                .offset(x: 10, y: -8)
                        }
                    }
                }
            }

            fabCircle {
                NavigationLink {
                    SpotSearchView(
                        latitude: location.coordinate?.latitude ?? visibleRegion?.center.latitude ?? 0,
                        longitude: location.coordinate?.longitude ?? visibleRegion?.center.longitude ?? 0
                    )
                } label: {
                    Image("MapSearch").resizable().scaledToFit().frame(width: 16, height: 16)
                }
            }
        }
    }

    private var mapSideStack: some View {
        VStack(spacing: 12) {
            VStack(spacing: 0) {
                NavigationLink {
                    NearbyView(
                        latitude: location.coordinate?.latitude ?? visibleRegion?.center.latitude ?? 0,
                        longitude: location.coordinate?.longitude ?? visibleRegion?.center.longitude ?? 0
                    )
                } label: {
                    VStack(spacing: 4) {
                        Image("MapList").resizable().scaledToFit().frame(width: 14, height: 14)
                        Text(language.t("map.list"))
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(Theme.text)
                    }
                    .frame(width: 36, height: 50)
                }
                .buttonStyle(.plain)

                Divider().frame(width: 28)

                Group {
                    if auth.isLoggedIn {
                        NavigationLink {
                            CreateLandmarkView()
                        } label: {
                            sideAddLabel
                        }
                    } else {
                        Button { showLogin = true } label: { sideAddLabel }
                    }
                }
                .buttonStyle(.plain)
            }
            .background(Color.white, in: RoundedRectangle(cornerRadius: 10))
            .shadow(color: .black.opacity(0.2), radius: 4, y: 2)

            Button(action: recenter) {
                Image("MapLocation")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 18, height: 18)
                    .frame(width: 44, height: 44)
                    .background(Color.white, in: Circle())
                    .shadow(color: .black.opacity(0.2), radius: 4, y: 2)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(language.t("map.locate"))
        }
    }

    private var sideAddLabel: some View {
        VStack(spacing: 4) {
            Image("MapAdd").resizable().scaledToFit().frame(width: 14, height: 14)
            Text(language.t("map.landmark"))
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Theme.text)
        }
        .frame(width: 36, height: 50)
    }

    private var checkinCTA: some View {
        Group {
            if auth.isLoggedIn {
                NavigationLink {
                    CreateCheckinView()
                } label: {
                    Image("MapCheckin")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 80, height: 80)
                }
            } else {
                Button { showLogin = true } label: {
                    Image("MapCheckin")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 80, height: 80)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(language.t("checkin.create"))
    }

    // MARK: - Bottom sheet

    private func mapBottomSheet(height: CGFloat, expandedHeight: CGFloat) -> some View {
        VStack(spacing: 0) {
            sheetGrabber

            if let selected {
                selectedPreview(selected)
            } else {
                sheetListHeader
                topicChips
                sheetCheckinGrid
            }
        }
        // RN isTop: nudge content below the status bar when fully expanded.
        .padding(.top, sheetExpanded ? Theme.topSafeAreaInset : 0)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: sheetExpanded ? 0 : 16, style: .continuous))
        .shadow(color: .black.opacity(sheetExpanded ? 0 : 0.18), radius: 10, y: -2)
        .highPriorityGesture(sheetDragGesture, including: sheetExpanded ? .none : .all)
        // Expanded: allow downward pan from chrome even while the grid scrolls.
        .simultaneousGesture(sheetCollapseOnlyGesture, including: sheetExpanded ? .all : .none)
    }

    private var sheetGrabber: some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(Theme.sheetHandle)
                .frame(width: 35, height: 5)
                .padding(.top, 10)
                .padding(.bottom, 8)
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .gesture(sheetDragGesture)
    }

    private var sheetDragGesture: some Gesture {
        DragGesture(minimumDistance: 8, coordinateSpace: .local)
            .onChanged { value in
                // Prefer vertical intent so topic chips / taps still work.
                guard abs(value.translation.height) > abs(value.translation.width) else { return }
                if sheetExpanded {
                    sheetDragOffset = max(0, value.translation.height)
                } else {
                    sheetDragOffset = min(0, value.translation.height)
                }
            }
            .onEnded { value in
                let threshold: CGFloat = 48
                let velocity = value.predictedEndTranslation.height
                withAnimation(Self.sheetSpring) {
                    if sheetExpanded {
                        if value.translation.height > threshold || velocity > 350 {
                            sheetExpanded = false
                        }
                    } else if value.translation.height < -threshold || velocity < -350 {
                        sheetExpanded = true
                    }
                    sheetDragOffset = 0
                }
            }
    }

    /// Downward-only drag used while expanded (works alongside ScrollView).
    private var sheetCollapseOnlyGesture: some Gesture {
        DragGesture(minimumDistance: 24, coordinateSpace: .local)
            .onChanged { value in
                guard value.translation.height > 0,
                      abs(value.translation.height) > abs(value.translation.width)
                else { return }
                sheetDragOffset = value.translation.height
            }
            .onEnded { value in
                let velocity = value.predictedEndTranslation.height
                withAnimation(Self.sheetSpring) {
                    if value.translation.height > 80 || velocity > 500 {
                        sheetExpanded = false
                    }
                    sheetDragOffset = 0
                }
            }
    }

    private var recommendTitle: String {
        let city = recommendCity.trimmingCharacters(in: .whitespacesAndNewlines)
        let suffix = language.t("home.checkinRecommend")
        return city.isEmpty ? suffix : "\(city)\(suffix)"
    }

    private var sheetListHeader: some View {
        HStack(spacing: 8) {
            if sheetExpanded {
                Button {
                    withAnimation(Self.sheetSpring) {
                        sheetExpanded = false
                    }
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Theme.text)
                        .frame(width: 44, height: 36)
                }
                .buttonStyle(.plain)
            }
            Text(recommendTitle)
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(Theme.link)
                .lineLimit(1)
                .padding(.leading, sheetExpanded ? 0 : 16)
            Spacer(minLength: 0)
        }
        .padding(.bottom, 4)
        .contentShape(Rectangle())
        .gesture(sheetDragGesture)
    }

    private var topicChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                topicChip(id: 0, title: language.t("checkin.topicAll"))
                ForEach(tags) { tag in
                    let tid = tag.rawId ?? 0
                    topicChip(id: tid, title: "# \(tag.displayName)")
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .frame(height: 48)
    }

    private func topicChip(id: Int, title: String) -> some View {
        Button {
            topicId = id
        } label: {
            Text(title)
                .font(.system(size: 14))
                .foregroundStyle(topicId == id ? Theme.brand : Theme.text)
                .padding(.horizontal, 16)
                .frame(height: 32)
                .background(Theme.chipFill, in: RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(topicId == id ? Theme.brand : Color.clear, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    private var sheetCheckinGrid: some View {
        Group {
            if sheetLoading && checkins.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity, minHeight: 100)
            } else if checkins.isEmpty {
                Text(language.t("checkin.feedEmpty"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 100)
            } else {
                ScrollView {
                    LazyVGrid(
                        columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)],
                        spacing: 8
                    ) {
                        ForEach(checkins) { item in
                            NavigationLink {
                                CheckinDetailView(checkinId: item.checkin?.id ?? item.id)
                            } label: {
                                MapCheckinCell(item: item)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 12)

                    if sheetExpanded {
                        if sheetLoadingMore {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                        } else if sheetCanLoadMore {
                            Color.clear
                                .frame(height: 1)
                                .onAppear {
                                    Task { await loadMoreCheckins() }
                                }
                        }
                    }
                    Color.clear.frame(height: 24)
                }
                // Collapsed height is for peeking; don't let the grid eat expand swipes.
                .scrollDisabled(!sheetExpanded)
            }
        }
    }

    private func selectedPreview(_ item: SpotAnnotationItem) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(language.t("landmark.detail"))
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(Theme.link)
                Spacer()
                Button {
                    selected = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 16)

            NavigationLink {
                LandmarkDetailView(spotId: item.spot.spot_id)
            } label: {
                SpotPreviewCard(spot: item.spot)
                    .padding(.horizontal, 16)
            }
            .buttonStyle(.plain)

            Spacer(minLength: 0)
        }
    }

    // MARK: - Helpers

    private func fabCircle<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .frame(width: 36, height: 36)
            .background(Color.white, in: Circle())
            .shadow(color: .black.opacity(0.2), radius: 4, y: 2)
    }

    private func recenter() {
        location.requestPermissionAndLocate()
        guard let coordinate = location.coordinate else { return }
        applyUserLocation(coordinate, animated: true)
    }

    private func applyUserLocation(_ coordinate: CLLocationCoordinate2D, animated: Bool) {
        didCenterOnUser = true
        let region = MKCoordinateRegion(center: coordinate, span: Self.defaultSpan)
        visibleRegion = region
        let next: MapCameraPosition = .region(region)
        if animated {
            withAnimation { position = next }
        } else {
            position = next
        }
        scheduleFetch(for: region, debounceMs: 0)
        scheduleCheckins(debounceMs: 0)
        scheduleRecommendCity(for: coordinate, debounceMs: 0)
    }

    @MainActor
    private func bootstrapAroundUser() async {
        if let coordinate = location.coordinate {
            applyUserLocation(coordinate, animated: false)
            return
        }
        for _ in 0..<20 {
            try? await Task.sleep(nanoseconds: 150_000_000)
            if let coordinate = location.coordinate {
                applyUserLocation(coordinate, animated: true)
                return
            }
        }
    }

    private func scheduleFetch(for region: MKCoordinateRegion, debounceMs: UInt64) {
        spotsFetchID += 1
        let fetchID = spotsFetchID
        Task { @MainActor in
            if debounceMs > 0 {
                try? await Task.sleep(nanoseconds: debounceMs * 1_000_000)
            }
            guard fetchID == spotsFetchID else { return }
            await fetchSpots(in: region, fetchID: fetchID)
        }
    }

    private func scheduleCheckins(debounceMs: UInt64) {
        checkinsFetchID += 1
        let fetchID = checkinsFetchID
        Task { @MainActor in
            if debounceMs > 0 {
                try? await Task.sleep(nanoseconds: debounceMs * 1_000_000)
            }
            guard fetchID == checkinsFetchID else { return }
            await loadCheckins(reset: true, fetchID: fetchID)
        }
    }

    private func scheduleRecommendCity(for coordinate: CLLocationCoordinate2D, debounceMs: UInt64) {
        geocodeFetchID += 1
        let fetchID = geocodeFetchID
        Task { @MainActor in
            if debounceMs > 0 {
                try? await Task.sleep(nanoseconds: debounceMs * 1_000_000)
            }
            guard fetchID == geocodeFetchID else { return }
            if let payload = try? await SpotAPI.reverseAddress(
                latitude: coordinate.latitude,
                longitude: coordinate.longitude
            ) {
                let city = payload.city?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                recommendCity = city.isEmpty ? (payload.displayArea ?? "") : city
            }
        }
    }

    @MainActor
    private func loadMoreCheckins() async {
        guard sheetExpanded, sheetCanLoadMore, !sheetLoading, !sheetLoadingMore else { return }
        let fetchID = checkinsFetchID
        sheetLoadingMore = true
        defer { if fetchID == checkinsFetchID { sheetLoadingMore = false } }
        checkinPage += 1
        await loadCheckins(reset: false, fetchID: fetchID)
    }

    @MainActor
    private func fetchSpots(in region: MKCoordinateRegion, fetchID: Int) async {
        let halfLat = region.span.latitudeDelta / 2
        let halfLng = region.span.longitudeDelta / 2
        let swLat = region.center.latitude - halfLat
        let swLng = region.center.longitude - halfLng
        let neLat = region.center.latitude + halfLat
        let neLng = region.center.longitude + halfLng

        isLoading = true
        errorMessage = nil
        defer {
            if fetchID == spotsFetchID {
                isLoading = false
            }
        }

        do {
            let pithy = try await SpotAPI.listPithy(
                swLat: swLat, swLng: swLng, neLat: neLat, neLng: neLng, category: ""
            )
            guard fetchID == spotsFetchID else { return }
            if !pithy.isEmpty {
                spots = pithy.map(SpotAnnotationItem.init)
                return
            }

            let grids = try await SpotAPI.listGrid(
                swLat: swLat, swLng: swLng, neLat: neLat, neLng: neLng, category: ""
            )
            guard fetchID == spotsFetchID else { return }
            let points = grids.flatMap { $0.points ?? [] }
            spots = points.map(SpotAnnotationItem.init)
            if spots.isEmpty {
                errorMessage = language.t("map.empty")
            }
        } catch {
            guard fetchID == spotsFetchID else { return }
            if let api = error as? APIError, api.isCancellation { return }
            if APIError.isCancellation(error) { return }
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func loadCheckins(reset: Bool, fetchID: Int) async {
        let lat = location.coordinate?.latitude ?? visibleRegion?.center.latitude ?? Self.fallbackCoordinate.latitude
        let lng = location.coordinate?.longitude ?? visibleRegion?.center.longitude ?? Self.fallbackCoordinate.longitude
        if reset {
            checkinPage = 1
            sheetCanLoadMore = true
            sheetLoading = true
        }
        defer {
            if fetchID == checkinsFetchID {
                sheetLoading = false
            }
        }
        do {
            let fetched = try await CheckinAPI.feed(
                latitude: lat,
                longitude: lng,
                page: checkinPage,
                topicId: topicId
            )
            guard fetchID == checkinsFetchID else { return }
            if reset {
                checkins = fetched
            } else {
                let existing = Set(checkins.map(\.id))
                checkins.append(contentsOf: fetched.filter { !existing.contains($0.id) })
            }
            sheetCanLoadMore = fetched.count >= Self.checkinPageSize
            if !reset && fetched.isEmpty {
                sheetCanLoadMore = false
                checkinPage = max(1, checkinPage - 1)
            }
        } catch {
            guard fetchID == checkinsFetchID else { return }
            if !reset {
                checkinPage = max(1, checkinPage - 1)
            }
            if let api = error as? APIError, api.isCancellation { return }
            if APIError.isCancellation(error) { return }
        }
    }
}

// MARK: - Marker

private struct MapSpotMarkerView: View {
    let spot: MapSpot
    let selected: Bool

    private var categoryColor: Color {
        MapCategoryColor.color(for: spot.category ?? spot.category_en ?? "")
    }

    var body: some View {
        VStack(spacing: 2) {
            ZStack {
                Circle()
                    .fill(selected ? Color(red: 1, green: 0.153, blue: 0.239) : categoryColor)
                    .frame(width: selected ? 56 : 44, height: selected ? 56 : 44)
                    .overlay(Circle().stroke(Color.white, lineWidth: 2))
                    .shadow(color: .black.opacity(0.25), radius: 3, y: 2)

                AsyncImage(url: URL(string: spot.landmark_image ?? spot.category_image ?? "")) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    default:
                        Image("MarkerNormal").resizable().scaledToFill()
                    }
                }
                .frame(width: selected ? 44 : 34, height: selected ? 44 : 34)
                .clipShape(Circle())
            }

            if selected {
                Text(spot.title ?? "")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.ultraThinMaterial, in: Capsule())
            }
        }
    }
}

enum MapCategoryColor {
    static func color(for category: String) -> Color {
        switch category.lowercased() {
        case "business", "diet", "entertainment", "shopping", "shop", "restaurant":
            return Color(red: 1, green: 0.365, blue: 0)
        case "culture", "education", "health", "sports":
            return Color(red: 0.604, green: 0.506, blue: 0.976)
        case "government", "services", "park":
            return Color(red: 0.098, green: 0.651, blue: 0.451)
        default:
            return Color(red: 0.176, green: 0.529, blue: 1)
        }
    }
}

private struct MapCheckinCell: View {
    let item: CheckinFeedItem

    private var imageURL: String? {
        item.checkin?.images?.first?.image_url ?? item.point?.landmark_image
    }

    private var avatarURL: String? {
        item.user?.avatar_url ?? item.checkin?.user?.avatar_url
    }

    private var nickname: String {
        item.user?.nickname ?? item.checkin?.user?.nickname ?? "User"
    }

    private var liked: Bool {
        item.is_liked == true || item.checkin?.is_liked == true
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Color.clear
                .aspectRatio(1, contentMode: .fit)
                .overlay {
                    AsyncImage(url: URL(string: imageURL ?? "")) { phase in
                        switch phase {
                        case .success(let image):
                            image.resizable().scaledToFill()
                        default:
                            Theme.chipFill
                        }
                    }
                }
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: 10))

            Text(item.checkin?.content ?? item.point?.title ?? "")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.text)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 4) {
                if let location = item.point?.location, !location.isEmpty {
                    Image(systemName: "mappin")
                        .font(.system(size: 9))
                    Text(location)
                        .lineLimit(1)
                }
                if let distance = item.distance {
                    if item.point?.location?.isEmpty == false {
                        Text("·")
                    }
                    Text(Theme.formatDistance(distance))
                }
            }
            .font(.system(size: 10))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 6) {
                AsyncImage(url: URL(string: avatarURL ?? "")) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    default:
                        Image("DefaultAvatar").resizable().scaledToFill()
                    }
                }
                .frame(width: 18, height: 18)
                .clipShape(Circle())

                Text(nickname)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Spacer(minLength: 0)

                Image(systemName: liked ? "heart.fill" : "heart")
                    .font(.system(size: 10))
                    .foregroundStyle(liked ? Color.red : .secondary)
                Text("\(item.checkin?.like_count ?? 0)")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct SpotPreviewCard: View {
    let spot: MapSpot

    var body: some View {
        HStack(spacing: 12) {
            AsyncImage(url: URL(string: spot.landmark_image ?? "")) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFill()
                default:
                    Image("DefaultAvatar").resizable().scaledToFill()
                }
            }
            .frame(width: 64, height: 64)
            .clipShape(RoundedRectangle(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 4) {
                Text(spot.title ?? "Spot")
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(spot.location ?? spot.category ?? "")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                HStack(spacing: 12) {
                    Label("\(spot.like_count ?? 0)", systemImage: "heart")
                    Label("\(spot.checkin_count ?? 0)", systemImage: "checkmark.circle")
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .foregroundStyle(.tertiary)
        }
        .padding(12)
        .background(Theme.chipFill, in: RoundedRectangle(cornerRadius: 16))
    }
}
