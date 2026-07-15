import SwiftUI

struct MyLandmarksView: View {
    @Environment(LanguageManager.self) private var language

    @State private var status = 1
    @State private var keyword = ""
    @State private var items: [OwnedSpotRow] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var editSpotId: Int?

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $status) {
                Text(language.t("landmark.active")).tag(1)
                Text(language.t("landmark.inactive")).tag(0)
            }
            .pickerStyle(.segmented)
            .padding()

            if isLoading && items.isEmpty {
                ProgressView(language.t("common.loading"))
                Spacer()
            } else if let errorMessage, items.isEmpty {
                ContentUnavailableView {
                    Label(language.t("common.error"), systemImage: "exclamationmark.triangle")
                } description: {
                    Text(errorMessage)
                } actions: {
                    Button(language.t("common.retry")) { Task { await load() } }
                }
            } else if items.isEmpty {
                ContentUnavailableView(language.t("landmark.myEmpty"), systemImage: "mappin.slash")
            } else {
                List(items) { item in
                    let spotId = item.point?.resolvedId ?? item.id
                    NavigationLink {
                        LandmarkDetailView(spotId: spotId)
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
                    .swipeActions(edge: .trailing) {
                        Button {
                            editSpotId = spotId
                        } label: {
                            Label(language.t("landmark.edit"), systemImage: "pencil")
                        }
                        .tint(.blue)
                    }
                    .contextMenu {
                        Button {
                            editSpotId = spotId
                        } label: {
                            Label(language.t("landmark.edit"), systemImage: "pencil")
                        }
                    }
                }
                .listStyle(.plain)
                .navigationDestination(item: $editSpotId) { id in
                    ModifyLandmarkView(spotId: id)
                }
            }
        }
        .navigationTitle(language.t("landmark.myList"))
        .searchable(text: $keyword, prompt: language.t("search.placeholder"))
        .onChange(of: status) { _, _ in Task { await load() } }
        .onSubmit(of: .search) { Task { await load() } }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink {
                    CreateLandmarkView()
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .task { await load() }
        .refreshable { await load() }
    }

    @MainActor
    private func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let response = try await SpotAPI.mySpots(
                status: status,
                page: 1,
                keyword: keyword.trimmingCharacters(in: .whitespacesAndNewlines)
            )
            items = response.points ?? []
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
