import SwiftUI
import PhotosUI

struct CreateCheckinView: View {
    @Environment(LanguageManager.self) private var language
    @Environment(\.dismiss) private var dismiss

    @State private var spotId: Int?
    @State private var spotTitle: String
    @State private var content = ""
    @State private var selectedItems: [PhotosPickerItem] = []
    @State private var images: [UIImage] = []
    @State private var isPrivate = false
    @State private var availableTags: [CheckinTag] = []
    @State private var selectedTagIds: Set<String> = []
    @State private var restrict: CheckinPublishRestrict?
    @State private var isPublishing = false
    @State private var errorMessage: String?
    @State private var createdCheckinId: Int?
    @State private var showCreatedDetail = false
    @State private var showSpotPicker = false
    @State private var showVip = false

    init(spotId: Int? = nil, spotTitle: String = "") {
        _spotId = State(initialValue: spotId)
        _spotTitle = State(initialValue: spotTitle)
    }

    var body: some View {
        Form {
            Section(language.t("checkin.pickLandmark")) {
                Button {
                    showSpotPicker = true
                } label: {
                    HStack {
                        Label(
                            spotTitle.isEmpty ? language.t("checkin.chooseLandmark") : spotTitle,
                            systemImage: "mappin.and.ellipse"
                        )
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
            }

            Section {
                TextField(language.t("checkin.content"), text: $content, axis: .vertical)
                    .lineLimit(4...8)
            }

            Section {
                PhotosPicker(
                    selection: $selectedItems,
                    maxSelectionCount: 6,
                    matching: .images
                ) {
                    Label(language.t("checkin.addPhotos"), systemImage: "photo.on.rectangle.angled")
                }
                .onChange(of: selectedItems) { _, newItems in
                    Task { await loadImages(from: newItems) }
                }

                if !images.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack {
                            ForEach(Array(images.enumerated()), id: \.offset) { index, image in
                                Image(uiImage: image)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 88, height: 88)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                    .overlay(alignment: .topTrailing) {
                                        Button {
                                            images.remove(at: index)
                                        } label: {
                                            Image(systemName: "xmark.circle.fill")
                                                .foregroundStyle(.white, .black.opacity(0.6))
                                        }
                                        .padding(4)
                                    }
                            }
                        }
                    }
                }
            }

            Section(language.t("checkin.tags")) {
                if availableTags.isEmpty {
                    Text(language.t("checkin.tagsEmpty"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    FlexibleTagWrap(tags: availableTags, selected: $selectedTagIds)
                }
            }

            Section {
                Toggle(language.t("checkin.private"), isOn: $isPrivate)
            }

            if let restrict {
                Section {
                    Button {
                        showVip = true
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(language.t("checkin.quotaLeft")) \(restrict.remaining)")
                                .font(.subheadline)
                            Text(language.t("checkin.vipUpsell"))
                                .font(.caption)
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                }
            }

            if let errorMessage {
                Section {
                    Text(errorMessage).foregroundStyle(.red)
                }
            }
        }
        .navigationTitle(language.t("checkin.create"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(language.t("checkin.publish")) {
                    Task { await publish() }
                }
                .disabled(
                    isPublishing
                        || spotId == nil
                        || (content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && images.isEmpty)
                )
            }
        }
        .overlay {
            if isPublishing {
                ZStack {
                    Color.black.opacity(0.2).ignoresSafeArea()
                    ProgressView(language.t("common.loading"))
                        .padding()
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
            }
        }
        .navigationDestination(isPresented: $showCreatedDetail) {
            if let createdCheckinId {
                CheckinDetailView(checkinId: createdCheckinId)
            }
        }
        .navigationDestination(isPresented: $showVip) {
            VipPayView()
        }
        .sheet(isPresented: $showSpotPicker) {
            NavigationStack {
                SpotPickView { id, title in
                    spotId = id
                    spotTitle = title
                }
            }
        }
        .task {
            availableTags = (try? await CheckinAPI.tags()) ?? []
            restrict = try? await CheckinAPI.publishRestrict()
        }
    }

    @MainActor
    private func loadImages(from items: [PhotosPickerItem]) async {
        var loaded: [UIImage] = []
        for item in items {
            if let data = try? await item.loadTransferable(type: Data.self),
               let image = UIImage(data: data) {
                loaded.append(image)
            }
        }
        images = loaded
    }

    @MainActor
    private func publish() async {
        guard let spotId else {
            errorMessage = language.t("checkin.requireLandmark")
            return
        }
        if let restrict, restrict.remaining <= 0, restrict.can_publish != true {
            errorMessage = language.t("checkin.quotaExhausted")
            showVip = true
            return
        }
        isPublishing = true
        errorMessage = nil
        defer { isPublishing = false }
        do {
            var urls: [String] = []
            for image in images {
                let url = try await CheckinAPI.uploadImage(image)
                urls.append(url)
            }
            let tags = availableTags
                .filter { selectedTagIds.contains($0.resolvedId) }
                .map(\.resolvedId)
            let checkin = try await CheckinAPI.create(
                spotId: spotId,
                content: content.trimmingCharacters(in: .whitespacesAndNewlines),
                imageURLs: urls,
                tags: tags,
                isPrivate: isPrivate
            )
            createdCheckinId = checkin.id
            showCreatedDetail = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct FlexibleTagWrap: View {
    let tags: [CheckinTag]
    @Binding var selected: Set<String>

    var body: some View {
        FlowLayout(spacing: 8) {
            ForEach(tags) { tag in
                let isOn = selected.contains(tag.resolvedId)
                Button {
                    if isOn {
                        selected.remove(tag.resolvedId)
                    } else {
                        selected.insert(tag.resolvedId)
                    }
                } label: {
                    Text("# \(tag.displayName)")
                        .font(.caption)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(isOn ? Color.accentColor.opacity(0.15) : Color.gray.opacity(0.12))
                        .foregroundStyle(isOn ? Color.accentColor : .secondary)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(isOn ? Color.accentColor : Color.secondary.opacity(0.35), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }
}

private struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(proposal: proposal, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(proposal: proposal, subviews: subviews)
        for (index, frame) in result.frames.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                proposal: ProposedViewSize(frame.size)
            )
        }
    }

    private func arrange(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, frames: [CGRect]) {
        let maxWidth = proposal.width ?? .infinity
        var frames: [CGRect] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var maxX: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            frames.append(CGRect(origin: CGPoint(x: x, y: y), size: size))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
            maxX = max(maxX, x - spacing)
        }

        return (CGSize(width: maxX, height: y + rowHeight), frames)
    }
}
