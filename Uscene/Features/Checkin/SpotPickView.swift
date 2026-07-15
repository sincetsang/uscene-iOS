import SwiftUI

struct SpotPickView: View {
    @Environment(LanguageManager.self) private var language
    @Environment(LocationManager.self) private var location
    @Environment(\.dismiss) private var dismiss

    var onPick: (Int, String) -> Void

    @State private var keyword = ""
    @State private var items: [NearbySpotItem] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var searchTask: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField(language.t("search.placeholder"), text: $keyword)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.search)
                    .onSubmit { Task { await search() } }
            }
            .padding(12)
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .padding()

            if isLoading {
                ProgressView().padding()
            } else if let errorMessage {
                Text(errorMessage).font(.caption).foregroundStyle(.red).padding()
            } else if items.isEmpty {
                ContentUnavailableView(language.t("checkin.pickLandmarkEmpty"), systemImage: "mappin.slash")
            } else {
                List(items) { item in
                    Button {
                        onPick(item.point.resolvedId, item.displayTitle)
                        dismiss()
                    } label: {
                        NearbyRow(item: item)
                    }
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle(language.t("checkin.pickLandmark"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(language.t("common.cancel")) { dismiss() }
            }
        }
        .task { await loadNearby() }
        .onChange(of: keyword) { _, value in
            searchTask?.cancel()
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                Task { await loadNearby() }
                return
            }
            searchTask = Task {
                try? await Task.sleep(nanoseconds: 350_000_000)
                guard !Task.isCancelled else { return }
                await search()
            }
        }
    }

    @MainActor
    private func loadNearby() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let lat = location.coordinate?.latitude ?? 22.2987
            let lng = location.coordinate?.longitude ?? 114.1723
            items = try await SpotAPI.nearby(latitude: lat, longitude: lng)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func search() async {
        let key = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else {
            await loadNearby()
            return
        }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let lat = location.coordinate?.latitude ?? 22.2987
            let lng = location.coordinate?.longitude ?? 114.1723
            items = try await SpotAPI.search(latitude: lat, longitude: lng, keyword: key)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
