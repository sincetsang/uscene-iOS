import SwiftUI
import PhotosUI

struct CreateProductView: View {
    @Environment(LanguageManager.self) private var language
    @Environment(\.dismiss) private var dismiss

    var spotId: Int?
    var editingProductId: Int?

    @State private var selectedSpotId: Int?
    @State private var mySpots: [OwnedSpotRow] = []
    @State private var name = ""
    @State private var descriptionText = ""
    @State private var priceText = ""
    @State private var currency = "USDT"
    @State private var allTags: [ProductTag] = []
    @State private var selectedTags: Set<String> = []
    @State private var existingImages: [SpotImage] = []
    @State private var deleteImageIds: [Int] = []
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var newImages: [UIImage] = []
    @State private var isLoading = false
    @State private var isSubmitting = false
    @State private var errorMessage: String?

    private var resolvedSpotId: Int? { selectedSpotId ?? spotId }

    var body: some View {
        Form {
            if editingProductId == nil {
                Section(language.t("product.spot")) {
                    if mySpots.isEmpty {
                        Text(language.t("landmark.myEmpty"))
                            .foregroundStyle(.secondary)
                    } else {
                        Picker(language.t("product.spot"), selection: $selectedSpotId) {
                            Text("-").tag(Int?.none)
                            ForEach(mySpots) { row in
                                Text(row.displayTitle).tag(Optional(row.point?.resolvedId ?? row.id))
                            }
                        }
                    }
                }
            }

            Section(language.t("product.basic")) {
                TextField(language.t("product.name"), text: $name)
                TextField(language.t("product.description"), text: $descriptionText, axis: .vertical)
                    .lineLimit(3...6)
            }

            Section(language.t("product.price")) {
                Picker(language.t("product.currency"), selection: $currency) {
                    Text("USDT").tag("USDT")
                    Text("FEC").tag("FEC")
                }
                .pickerStyle(.segmented)
                TextField(language.t("product.priceAmount"), text: $priceText)
                    .keyboardType(.decimalPad)
            }

            Section(language.t("product.tags")) {
                if allTags.isEmpty {
                    Text(language.t("common.loading")).foregroundStyle(.secondary)
                } else {
                    FlowTagPicker(tags: allTags, selected: $selectedTags)
                }
            }

            Section(language.t("product.photos")) {
                if !existingImages.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack {
                            ForEach(existingImages, id: \.image_url) { image in
                                ZStack(alignment: .topTrailing) {
                                    AsyncImage(url: URL(string: image.image_url ?? "")) { phase in
                                        switch phase {
                                        case .success(let img): img.resizable().scaledToFill()
                                        default: Color.gray.opacity(0.12)
                                        }
                                    }
                                    .frame(width: 72, height: 72)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                    Button {
                                        if let id = image.id { deleteImageIds.append(id) }
                                        existingImages.removeAll { $0.image_url == image.image_url }
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .foregroundStyle(.white, .black.opacity(0.55))
                                    }
                                    .padding(2)
                                }
                            }
                        }
                    }
                }
                PhotosPicker(selection: $pickerItems, maxSelectionCount: 6, matching: .images) {
                    Label(language.t("checkin.addPhotos"), systemImage: "photo.on.rectangle")
                }
                .onChange(of: pickerItems) { _, items in
                    Task { await loadNewImages(items) }
                }
                if !newImages.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack {
                            ForEach(Array(newImages.enumerated()), id: \.offset) { _, image in
                                Image(uiImage: image)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 72, height: 72)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                        }
                    }
                }
            }

            if let errorMessage {
                Section { Text(errorMessage).foregroundStyle(.red) }
            }
        }
        .navigationTitle(editingProductId == nil ? language.t("product.create") : language.t("product.edit"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(language.t("common.done")) {
                    Task { await submit() }
                }
                .disabled(isSubmitting || isLoading)
            }
        }
        .overlay {
            if isSubmitting || isLoading {
                ProgressView().padding().background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            }
        }
        .task { await bootstrap() }
    }

    @MainActor
    private func bootstrap() async {
        isLoading = true
        defer { isLoading = false }
        do {
            async let tagsTask = CommerceAPI.tags()
            async let spotsTask = SpotAPI.mySpots(status: 1, page: 1)
            allTags = (try? await tagsTask) ?? []
            if editingProductId == nil {
                mySpots = (try? await spotsTask)?.points ?? []
                if selectedSpotId == nil { selectedSpotId = spotId }
            }
            if let editingProductId {
                let detail = try await CommerceAPI.productDetail(productId: editingProductId, isOwner: 1)
                name = detail.name ?? ""
                descriptionText = detail.description ?? ""
                existingImages = detail.images ?? []
                selectedTags = Set((detail.tags ?? []).compactMap(\.mark))
                if let usd = detail.amount_usd, usd > 0 {
                    currency = "USDT"
                    priceText = String(format: "%g", usd)
                } else if let amount = detail.amount {
                    currency = "FEC"
                    priceText = String(format: "%g", amount)
                }
                selectedSpotId = detail.spot_id ?? spotId
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func loadNewImages(_ items: [PhotosPickerItem]) async {
        var loaded: [UIImage] = []
        for item in items {
            if let data = try? await item.loadTransferable(type: Data.self),
               let image = UIImage(data: data) {
                loaded.append(image)
            }
        }
        newImages = loaded
    }

    @MainActor
    private func submit() async {
        errorMessage = nil
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            errorMessage = language.t("product.requireName")
            return
        }
        guard let price = Double(priceText.trimmingCharacters(in: .whitespacesAndNewlines)), price > 0 else {
            errorMessage = language.t("product.requirePrice")
            return
        }
        let hasPhotos = !newImages.isEmpty || !existingImages.isEmpty
        guard hasPhotos else {
            errorMessage = language.t("product.requirePhoto")
            return
        }

        isSubmitting = true
        defer { isSubmitting = false }
        do {
            var keys: [String] = []
            for image in newImages {
                keys.append(try await MediaAPI.uploadForSpot(image))
            }
            let payment = ProductPayment(
                chain: currency == "USDT" ? "ETH" : "FEC",
                currency: currency,
                amount: price
            )
            let tagMarks = Array(selectedTags)

            if let editingProductId {
                try await CommerceAPI.updateProduct(
                    UpdateSellerProductBody(
                        product_id: editingProductId,
                        name: trimmedName,
                        description: descriptionText,
                        image_urls: keys,
                        tags: tagMarks,
                        payments: [payment],
                        delete_image_ids: deleteImageIds
                    )
                )
            } else {
                guard let spot = resolvedSpotId, spot > 0 else {
                    errorMessage = language.t("product.requireSpot")
                    return
                }
                try await CommerceAPI.createProduct(
                    CreateSellerProductBody(
                        spot_id: spot,
                        name: trimmedName,
                        description: descriptionText,
                        image_urls: keys,
                        tags: tagMarks,
                        payments: [payment]
                    )
                )
            }
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct FlowTagPicker: View {
    let tags: [ProductTag]
    @Binding var selected: Set<String>

    private let columns = [GridItem(.adaptive(minimum: 72), spacing: 8)]

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
            ForEach(tags) { tag in
                let mark = tag.mark ?? tag.id
                let isOn = selected.contains(mark)
                Button {
                    if isOn { selected.remove(mark) } else { selected.insert(mark) }
                } label: {
                    Text(tag.displayName)
                        .font(.caption)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .background(isOn ? Color.accentColor.opacity(0.2) : Color.gray.opacity(0.12), in: Capsule())
                        .foregroundStyle(isOn ? Color.accentColor : .primary)
                }
                .buttonStyle(.plain)
            }
        }
    }
}
