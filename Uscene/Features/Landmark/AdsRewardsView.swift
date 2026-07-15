import SwiftUI
import RiveRuntime

struct AdsRewardsView: View {
    @Environment(LanguageManager.self) private var language
    @Environment(AuthStore.self) private var auth
    @Environment(LocationManager.self) private var location

    @State private var items: [AdvertisementItem] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var actingId: Int?
    @State private var showLogin = false
    @State private var rewardAmountText: String?
    @State private var showReward = false

    var body: some View {
        Group {
            if isLoading && items.isEmpty {
                ProgressView(language.t("common.loading"))
            } else if let errorMessage, items.isEmpty {
                ContentUnavailableView(language.t("common.error"), systemImage: "exclamationmark.triangle", description: Text(errorMessage))
            } else if items.isEmpty {
                ContentUnavailableView(language.t("ads.empty"), systemImage: "gift")
            } else {
                List(items) { ad in
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(alignment: .top, spacing: 12) {
                            AsyncImage(url: URL(string: ad.image_url ?? "")) { phase in
                                switch phase {
                                case .success(let image): image.resizable().scaledToFill()
                                default: Color.gray.opacity(0.12)
                                }
                            }
                            .frame(width: 72, height: 72)
                            .clipShape(RoundedRectangle(cornerRadius: 8))

                            VStack(alignment: .leading, spacing: 4) {
                                Text(ad.title ?? language.t("ads.reward"))
                                    .font(.headline)
                                Text(ad.description ?? "")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(3)
                                if let amount = ad.reward_amount {
                                    Text("\(amount) \(ad.reward_currency ?? "")")
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(Color.accentColor)
                                }
                            }
                        }

                        HStack {
                            if let spotId = ad.check_in_point_id {
                                NavigationLink {
                                    LandmarkDetailView(spotId: spotId)
                                } label: {
                                    Text(language.t("landmark.detail"))
                                }
                            }
                            Spacer()
                            Button(language.t("ads.claim")) {
                                Task { await claim(ad) }
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(actingId != nil)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .navigationTitle(language.t("ads.title"))
        .sheet(isPresented: $showLogin) { NavigationStack { LoginView() } }
        .sheet(isPresented: $showReward) {
            NavigationStack {
                if let rewardAmountText {
                    LandRewardRiveView(amountText: rewardAmountText) {
                        showReward = false
                    }
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button(language.t("common.done")) { showReward = false }
                        }
                    }
                }
            }
            .presentationDetents([.medium])
        }
        .task { await load() }
        .refreshable { await load() }
    }

    @MainActor
    private func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        let lat = location.coordinate?.latitude ?? 22.2987
        let lng = location.coordinate?.longitude ?? 114.1723
        do {
            items = try await SystemAPI.advertisements(latitude: lat, longitude: lng)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func claim(_ ad: AdvertisementItem) async {
        guard auth.isLoggedIn else {
            showLogin = true
            return
        }
        actingId = ad.id
        defer { actingId = nil }
        do {
            try await SystemAPI.claimAd(advertisementId: ad.advertisement_id ?? ad.id)
            if let amount = ad.reward_amount {
                rewardAmountText = "+\(amount) \(ad.reward_currency ?? "")"
                showReward = true
            }
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
