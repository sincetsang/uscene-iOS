import SwiftUI
import PhotosUI
import MapKit

struct ModifyLandmarkView: View {
    @Environment(LanguageManager.self) private var language
    @Environment(\.dismiss) private var dismiss

    let spotId: Int

    @State private var title = ""
    @State private var descriptionText = ""
    @State private var checkCode = ""
    @State private var telegram = ""
    @State private var whatsapp = ""
    @State private var wechat = ""
    @State private var believeId = ""
    @State private var pcn = ""
    @State private var externalURL = ""
    @State private var categories: [CategoryItem] = []
    @State private var selectedCategory: CategoryItem?
    @State private var existingImages: [SpotImage] = []
    @State private var deleteImageIds: [Int] = []
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var newImages: [UIImage] = []
    @State private var coordinate = CLLocationCoordinate2D(latitude: 22.2987, longitude: 114.1723)
    @State private var locationText = ""
    @State private var country = ""
    @State private var province = ""
    @State private var city = ""
    @State private var cameraPosition: MapCameraPosition = .automatic
    @State private var isLoading = true
    @State private var isSubmitting = false
    @State private var errorMessage: String?
    @State private var step = 0
    @State private var confirmDiscard = false
    @State private var isDirty = false
    @State private var codes: [VerificationCode] = []

    var body: some View {
        Form {
            if isLoading {
                ProgressView(language.t("common.loading"))
            } else {
                Section {
                    HStack(spacing: 8) {
                        stepChip(0, title: language.t("landmark.basic"))
                        Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
                        stepChip(1, title: language.t("landmark.contacts"))
                    }
                    .listRowBackground(Color.clear)
                }

                if step == 0 {
                    stepOneSections
                } else {
                    stepTwoSections
                }

                if let errorMessage {
                    Section { Text(errorMessage).foregroundStyle(.red) }
                }
            }
        }
        .navigationTitle(language.t("landmark.edit"))
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button {
                    if isDirty {
                        confirmDiscard = true
                    } else if step > 0 {
                        step = 0
                    } else {
                        dismiss()
                    }
                } label: {
                    Image(systemName: "chevron.left")
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                if step == 0 {
                    Button(language.t("common.next")) {
                        if validateStepOne() { step = 1 }
                    }
                    .disabled(isLoading)
                } else {
                    Button(language.t("common.done")) {
                        Task { await submit() }
                    }
                    .disabled(isSubmitting || isLoading)
                }
            }
        }
        .confirmationDialog(language.t("landmark.discardConfirm"), isPresented: $confirmDiscard, titleVisibility: .visible) {
            Button(language.t("landmark.discard"), role: .destructive) { dismiss() }
            Button(language.t("common.cancel"), role: .cancel) {}
        }
        .overlay {
            if isSubmitting {
                ZStack {
                    Color.black.opacity(0.2).ignoresSafeArea()
                    ProgressView(language.t("common.loading"))
                        .padding()
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
            }
        }
        .task { await load() }
        .onChange(of: title) { _, _ in isDirty = true }
        .onChange(of: descriptionText) { _, _ in isDirty = true }
        .onChange(of: checkCode) { _, _ in isDirty = true }
        .onChange(of: newImages.count) { _, _ in isDirty = true }
        .onChange(of: deleteImageIds.count) { _, _ in isDirty = true }
    }

    @ViewBuilder
    private var stepOneSections: some View {
        Section(language.t("landmark.basic")) {
            TextField(language.t("landmark.title"), text: $title)
            TextField(language.t("landmark.description"), text: $descriptionText, axis: .vertical)
                .lineLimit(3...6)
        }

        Section(language.t("landmark.category")) {
            Picker(language.t("landmark.category"), selection: $selectedCategory) {
                Text("-").tag(CategoryItem?.none)
                ForEach(categories) { category in
                    Text(category.displayName).tag(Optional(category))
                }
            }
        }

        Section(language.t("landmark.photos")) {
            if !existingImages.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
                        ForEach(existingImages, id: \.image_url) { image in
                            ZStack(alignment: .topTrailing) {
                                AsyncImage(url: URL(string: image.image_url ?? "")) { phase in
                                    switch phase {
                                    case .success(let img):
                                        img.resizable().scaledToFill()
                                    default:
                                        Color.gray.opacity(0.12)
                                    }
                                }
                                .frame(width: 72, height: 72)
                                .clipShape(RoundedRectangle(cornerRadius: 8))

                                Button {
                                    if let id = image.id {
                                        deleteImageIds.append(id)
                                    }
                                    existingImages.removeAll { $0.id == image.id }
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

        Section(language.t("landmark.location")) {
            MapReader { proxy in
                Map(position: $cameraPosition) {
                    Marker(language.t("landmark.pin"), coordinate: coordinate)
                }
                .frame(height: 180)
                .onTapGesture { position in
                    if let coord = proxy.convert(position, from: .local) {
                        coordinate = coord
                        isDirty = true
                        Task { await refreshAddress() }
                    }
                }
            }
            TextField(language.t("landmark.address"), text: $locationText)
        }

        Section(language.t("landmark.checkCode")) {
            if !codes.isEmpty {
                Picker(language.t("landmark.checkCode"), selection: $checkCode) {
                    Text("-").tag("")
                    ForEach(codes) { item in
                        Text(item.value).tag(item.value)
                    }
                }
            }
            TextField(language.t("landmark.checkCodeManual"), text: $checkCode)
                .textInputAutocapitalization(.characters)
        }
    }

    @ViewBuilder
    private var stepTwoSections: some View {
        Section {
            VStack(alignment: .leading, spacing: 6) {
                Text(title.isEmpty ? "-" : title).font(.headline)
                Text(selectedCategory?.displayName ?? "-").font(.caption).foregroundStyle(.secondary)
                Text(locationText.isEmpty ? "-" : locationText).font(.caption).foregroundStyle(.secondary)
                let photoCount = existingImages.count + newImages.count
                Text("\(photoCount) \(language.t("landmark.photos"))").font(.caption2).foregroundStyle(.tertiary)
            }
        } header: {
            Text(language.t("landmark.preview"))
        }

        Section(language.t("landmark.contacts")) {
            TextField(language.t("contact.telegram"), text: $telegram)
                .textInputAutocapitalization(.never)
                .onChange(of: telegram) { _, _ in isDirty = true }
            TextField(language.t("contact.whatsapp"), text: $whatsapp)
                .keyboardType(.phonePad)
                .onChange(of: whatsapp) { _, _ in isDirty = true }
            TextField(language.t("contact.wechat"), text: $wechat)
                .onChange(of: wechat) { _, _ in isDirty = true }
            TextField(language.t("contact.believe"), text: $believeId)
                .textInputAutocapitalization(.never)
                .onChange(of: believeId) { _, _ in isDirty = true }
            TextField(language.t("contact.pcn"), text: $pcn)
                .textInputAutocapitalization(.never)
                .onChange(of: pcn) { _, _ in isDirty = true }
            TextField(language.t("contact.website"), text: $externalURL)
                .textInputAutocapitalization(.never)
                .keyboardType(.URL)
                .onChange(of: externalURL) { _, _ in isDirty = true }
        }
    }

    private func stepChip(_ index: Int, title: String) -> some View {
        Text(title)
            .font(.caption.weight(step == index ? .semibold : .regular))
            .foregroundStyle(step == index ? Theme.brand : .secondary)
    }

    private func validateStepOne() -> Bool {
        errorMessage = nil
        if title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errorMessage = language.t("landmark.requireTitle")
            return false
        }
        if selectedCategory?.categoryKey.isEmpty != false {
            errorMessage = language.t("landmark.requireCategory")
            return false
        }
        if existingImages.isEmpty && newImages.isEmpty {
            errorMessage = language.t("landmark.requirePhoto")
            return false
        }
        return true
    }

    @MainActor
    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            async let detailTask = SpotAPI.detail(spotId: spotId)
            async let catsTask = SpotAPI.categories()
            async let codesTask = UserAPI.verificationCodes(status: "unused")
            let detail = try await detailTask
            categories = (try? await catsTask) ?? []
            codes = (try? await codesTask) ?? []

            let point = detail.point
            title = point?.title ?? ""
            descriptionText = point?.description ?? point?.description_cn ?? ""
            locationText = point?.location ?? ""
            if let lat = point?.latitude, let lng = point?.longitude {
                coordinate = CLLocationCoordinate2D(latitude: lat, longitude: lng)
                cameraPosition = .region(
                    MKCoordinateRegion(
                        center: coordinate,
                        span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)
                    )
                )
            }
            existingImages = point?.images ?? detail.point_images ?? detail.images ?? []
            checkCode = point?.verification_code ?? ""
            telegram = point?.telegram_url ?? ""
            whatsapp = point?.whatsapp_url ?? ""
            wechat = point?.wechat ?? ""
            believeId = point?.believe_id ?? ""
            pcn = point?.pcn_url ?? ""
            externalURL = point?.external_url ?? ""
            let key = (point?.category ?? point?.category_en ?? "").lowercased()
            selectedCategory = categories.first {
                $0.categoryKey.lowercased() == key || ($0.type ?? "").lowercased() == key
            }
            isDirty = false
            // Fill country/province/city for update payload (SpotPoint may not carry them).
            await refreshAddress()
            isDirty = false
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
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else {
            errorMessage = language.t("landmark.requireTitle")
            return
        }
        guard let category = selectedCategory?.categoryKey, !category.isEmpty else {
            errorMessage = language.t("landmark.requireCategory")
            return
        }

        isSubmitting = true
        defer { isSubmitting = false }
        do {
            var keys: [String] = []
            for image in newImages {
                keys.append(try await MediaAPI.uploadForSpot(image))
            }
            let believeIdTrimmed = believeId.trimmingCharacters(in: .whitespacesAndNewlines)
            let believeURL: String
            if believeIdTrimmed.isEmpty {
                believeURL = ""
            } else {
                believeURL = (try? await SystemAPI.believeChatLink(believeId: believeIdTrimmed)) ?? ""
            }
            let body = UpdateSpotBody(
                spot_id: spotId,
                title: trimmedTitle,
                description: descriptionText,
                category: category,
                latitude: coordinate.latitude,
                longitude: coordinate.longitude,
                location: locationText,
                country: country,
                province: province,
                city: city,
                check_code: checkCode,
                image_urls: keys,
                delete_image_ids: deleteImageIds,
                external_url: externalURL,
                telegram_url: telegram,
                believe_id: believeId,
                believe_url: believeURL,
                pcn_url: pcn,
                whatsapp_url: whatsapp,
                wechat: wechat
            )
            try await SpotAPI.update(body)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func refreshAddress() async {
        if let payload = try? await SpotAPI.reverseAddress(latitude: coordinate.latitude, longitude: coordinate.longitude) {
            locationText = payload.displayAddress ?? locationText
            country = payload.country ?? country
            province = payload.province ?? province
            city = payload.city ?? city
        }
    }
}
