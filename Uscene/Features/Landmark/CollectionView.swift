import SwiftUI

struct CollectionView: View {
    @Environment(LanguageManager.self) private var language
    @Environment(AuthStore.self) private var auth

    @State private var items: [OwnedSpotRow] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showLogin = false

    var body: some View {
        Group {
            if !auth.isLoggedIn {
                ContentUnavailableView {
                    Label(language.t("login.pleaseLogin"), systemImage: "heart")
                } actions: {
                    Button(language.t("login.signIn")) { showLogin = true }
                }
            } else if isLoading && items.isEmpty {
                ProgressView(language.t("common.loading"))
            } else if let errorMessage, items.isEmpty {
                ContentUnavailableView(language.t("common.error"), systemImage: "exclamationmark.triangle", description: Text(errorMessage))
            } else if items.isEmpty {
                ContentUnavailableView(language.t("collection.empty"), systemImage: "heart.slash")
            } else {
                List(items) { item in
                    NavigationLink {
                        LandmarkDetailView(spotId: item.point?.resolvedId ?? item.id)
                    } label: {
                        HStack(spacing: 12) {
                            AsyncImage(url: URL(string: item.displayImage ?? "")) { phase in
                                switch phase {
                                case .success(let image): image.resizable().scaledToFill()
                                default: Color.gray.opacity(0.12)
                                }
                            }
                            .frame(width: 56, height: 56)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.displayTitle).font(.headline).lineLimit(1)
                                Text(item.point?.location ?? item.category ?? "")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle(language.t("collection.title"))
        .sheet(isPresented: $showLogin) { NavigationStack { LoginView() } }
        .task { await load() }
        .refreshable { await load() }
    }

    @MainActor
    private func load() async {
        guard auth.isLoggedIn else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            items = try await SpotAPI.likedList()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
