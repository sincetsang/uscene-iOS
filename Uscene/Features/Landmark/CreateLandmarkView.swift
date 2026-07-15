import SwiftUI
import PhotosUI
import MapKit

struct CreateLandmarkView: View {
    @Environment(LanguageManager.self) private var language
    @Environment(LocationManager.self) private var location
    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var description = ""
    @State private var checkCode = ""
    @State private var telegram = ""
    @State private var whatsapp = ""
    @State private var wechat = ""
    @State private var believeId = ""
    @State private var pcn = ""
    @State private var externalURL = ""
    @State private var categories: [CategoryItem] = []
    @State private var selectedCategory: CategoryItem?
    @State private var codes: [VerificationCode] = []
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var images: [UIImage] = []
    @State private var coordinate = CLLocationCoordinate2D(latitude: 22.2987, longitude: 114.1723)
    @State private var locationText = ""
    @State private var country = ""
    @State private var province = ""
    @State private var city = ""
    @State private var cameraPosition: MapCameraPosition = .region(
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 22.2987, longitude: 114.1723),
            span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)
        )
    )
    @State private var isSubmitting = false
    @State private var errorMessage: String?
    @State private var didCreate = false
    @State private var step = 0
    @State private var showSuccess = false
    @State private var confirmDiscard = false
    @State private var restoredDraftHint = false

    private var isDirty: Bool {
        !title.isEmpty || !description.isEmpty || !images.isEmpty || selectedCategory != nil || !checkCode.isEmpty
    }

    var body: some View {
        Form {
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
        .navigationTitle(language.t("landmark.create"))
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
                } else {
                    Button(language.t("common.done")) {
                        Task { await submit() }
                    }
                    .disabled(isSubmitting)
                }
            }
        }
        .confirmationDialog(language.t("landmark.discardConfirm"), isPresented: $confirmDiscard, titleVisibility: .visible) {
            Button(language.t("landmark.discard"), role: .destructive) {
                LandmarkDraftStore.clear()
                dismiss()
            }
            Button(language.t("common.cancel"), role: .cancel) {}
        }
        .sheet(isPresented: $showSuccess) {
            CreateLandmarkSuccessSheet(
                title: title,
                locationText: locationText,
                onCreateAnother: {
                    showSuccess = false
                    resetFormForAnother()
                },
                onBack: {
                    showSuccess = false
                    dismiss()
                }
            )
            .presentationDetents([.medium])
            .interactiveDismissDisabled()
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
        .task {
            if let coord = location.coordinate {
                coordinate = coord
                cameraPosition = .region(
                    MKCoordinateRegion(center: coord, span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02))
                )
            }
            async let cats = SpotAPI.categories()
            async let codeList = UserAPI.verificationCodes(status: "unused")
            categories = (try? await cats) ?? []
            codes = (try? await codeList) ?? []
            if restoreDraftIfNeeded() {
                restoredDraftHint = true
            } else {
                await refreshAddress()
            }
        }
        .onChange(of: title) { _, _ in persistDraft() }
        .onChange(of: description) { _, _ in persistDraft() }
        .onChange(of: checkCode) { _, _ in persistDraft() }
        .onChange(of: telegram) { _, _ in persistDraft() }
        .onChange(of: whatsapp) { _, _ in persistDraft() }
        .onChange(of: wechat) { _, _ in persistDraft() }
        .onChange(of: believeId) { _, _ in persistDraft() }
        .onChange(of: pcn) { _, _ in persistDraft() }
        .onChange(of: externalURL) { _, _ in persistDraft() }
        .onChange(of: locationText) { _, _ in persistDraft() }
        .onChange(of: selectedCategory?.categoryKey) { _, _ in persistDraft() }
        .alert(language.t("landmark.draftRestored"), isPresented: $restoredDraftHint) {
            Button(language.t("common.done"), role: .cancel) {}
        }
    }

    @ViewBuilder
    private var stepOneSections: some View {
            Section(language.t("landmark.basic")) {
                TextField(language.t("landmark.title"), text: $title)
                TextField(language.t("landmark.description"), text: $description, axis: .vertical)
                    .lineLimit(3...6)
            }

            Section(language.t("landmark.category")) {
                if categories.isEmpty {
                    Text(language.t("common.loading"))
                } else {
                    Picker(language.t("landmark.category"), selection: $selectedCategory) {
                        Text("-").tag(CategoryItem?.none)
                        ForEach(categories) { category in
                            Text(category.displayName).tag(Optional(category))
                        }
                    }
                }
            }

            Section(language.t("landmark.photos")) {
                PhotosPicker(selection: $pickerItems, maxSelectionCount: 6, matching: .images) {
                    Label(language.t("checkin.addPhotos"), systemImage: "photo.on.rectangle")
                }
                .onChange(of: pickerItems) { _, items in
                    Task { await loadImages(items) }
                }
                if !images.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack {
                            ForEach(Array(images.enumerated()), id: \.offset) { _, image in
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
                            Task { await refreshAddress() }
                        }
                    }
                }
                TextField(language.t("landmark.address"), text: $locationText)
                Button(language.t("map.locate")) {
                    if let coord = location.coordinate {
                        coordinate = coord
                        cameraPosition = .region(
                            MKCoordinateRegion(center: coord, span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02))
                        )
                        Task { await refreshAddress() }
                    }
                }
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
                    Text("\(images.count) \(language.t("landmark.photos"))").font(.caption2).foregroundStyle(.tertiary)
                }
            } header: {
                Text(language.t("landmark.preview"))
            }

            Section(language.t("landmark.contacts")) {
                TextField(language.t("contact.telegram"), text: $telegram)
                    .textInputAutocapitalization(.never)
                TextField(language.t("contact.whatsapp"), text: $whatsapp)
                    .keyboardType(.phonePad)
                TextField(language.t("contact.wechat"), text: $wechat)
                TextField(language.t("contact.believe"), text: $believeId)
                    .textInputAutocapitalization(.never)
                TextField(language.t("contact.pcn"), text: $pcn)
                    .textInputAutocapitalization(.never)
                TextField(language.t("contact.website"), text: $externalURL)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
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
        if images.isEmpty {
            errorMessage = language.t("landmark.requirePhoto")
            return false
        }
        if checkCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errorMessage = language.t("landmark.requireCode")
            return false
        }
        return true
    }

    @MainActor
    private func loadImages(_ items: [PhotosPickerItem]) async {
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
    private func refreshAddress() async {
        if let payload = try? await SpotAPI.reverseAddress(latitude: coordinate.latitude, longitude: coordinate.longitude) {
            locationText = payload.displayAddress ?? locationText
            country = payload.country ?? ""
            province = payload.province ?? ""
            city = payload.city ?? ""
            if let area = payload.displayArea, country.isEmpty && province.isEmpty && city.isEmpty {
                city = area
            }
        }
    }

    @MainActor
    private func resolveBelieveURL() async -> String {
        let id = believeId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty else { return "" }
        return (try? await SystemAPI.believeChatLink(believeId: id)) ?? ""
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
        guard !images.isEmpty else {
            errorMessage = language.t("landmark.requirePhoto")
            return
        }
        guard !checkCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            errorMessage = language.t("landmark.requireCode")
            return
        }

        isSubmitting = true
        defer { isSubmitting = false }
        do {
            var keys: [String] = []
            for image in images {
                keys.append(try await MediaAPI.uploadForSpot(image))
            }
            let believeURL = await resolveBelieveURL()
            let body = CreateSpotBody(
                title: trimmedTitle,
                latitude: coordinate.latitude,
                longitude: coordinate.longitude,
                location: locationText,
                country: country,
                province: province,
                city: city,
                image_urls: keys,
                category: category,
                check_code: checkCode.trimmingCharacters(in: .whitespacesAndNewlines),
                description: description,
                external_url: externalURL,
                telegram_url: telegram,
                believe_id: believeId,
                believe_url: believeURL,
                pcn_url: pcn,
                whatsapp_url: whatsapp,
                wechat: wechat
            )
            try await SpotAPI.create(body)
            didCreate = true
            LandmarkDraftStore.clear()
            showSuccess = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func persistDraft() {
        guard !didCreate else { return }
        LandmarkDraftStore.save(
            LandmarkDraft(
                title: title,
                description: description,
                checkCode: checkCode,
                telegram: telegram,
                whatsapp: whatsapp,
                wechat: wechat,
                believeId: believeId,
                pcn: pcn,
                externalURL: externalURL,
                categoryKey: selectedCategory?.categoryKey,
                latitude: coordinate.latitude,
                longitude: coordinate.longitude,
                locationText: locationText,
                country: country,
                province: province,
                city: city
            )
        )
    }

    @discardableResult
    private func restoreDraftIfNeeded() -> Bool {
        guard let draft = LandmarkDraftStore.load() else { return false }
        title = draft.title
        description = draft.description
        checkCode = draft.checkCode
        telegram = draft.telegram
        whatsapp = draft.whatsapp
        wechat = draft.wechat
        believeId = draft.believeId
        pcn = draft.pcn
        externalURL = draft.externalURL
        locationText = draft.locationText
        country = draft.country
        province = draft.province
        city = draft.city
        coordinate = CLLocationCoordinate2D(latitude: draft.latitude, longitude: draft.longitude)
        cameraPosition = .region(
            MKCoordinateRegion(center: coordinate, span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02))
        )
        if let key = draft.categoryKey, !key.isEmpty {
            selectedCategory = categories.first { $0.categoryKey == key }
        }
        return !title.isEmpty || !description.isEmpty || !checkCode.isEmpty
    }

    private func resetFormForAnother() {
        title = ""
        description = ""
        checkCode = ""
        telegram = ""
        whatsapp = ""
        wechat = ""
        believeId = ""
        pcn = ""
        externalURL = ""
        selectedCategory = nil
        pickerItems = []
        images = []
        step = 0
        didCreate = false
        errorMessage = nil
        LandmarkDraftStore.clear()
        Task { await refreshAddress() }
    }
}

private struct LandmarkDraft: Codable {
    var title: String
    var description: String
    var checkCode: String
    var telegram: String
    var whatsapp: String
    var wechat: String
    var believeId: String
    var pcn: String
    var externalURL: String
    var categoryKey: String?
    var latitude: Double
    var longitude: Double
    var locationText: String
    var country: String
    var province: String
    var city: String
}

private enum LandmarkDraftStore {
    private static let key = "landmark_draft"

    static func save(_ draft: LandmarkDraft) {
        guard let data = try? JSONEncoder().encode(draft) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    static func load() -> LandmarkDraft? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(LandmarkDraft.self, from: data)
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}

private struct CreateLandmarkSuccessSheet: View {
    @Environment(LanguageManager.self) private var language

    let title: String
    let locationText: String
    let onCreateAnother: () -> Void
    let onBack: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 52))
                .foregroundStyle(.green)
                .padding(.top, 12)

            Text(language.t("landmark.createSuccess"))
                .font(.title3.weight(.semibold))

            VStack(alignment: .leading, spacing: 6) {
                Text(title.isEmpty ? "-" : title)
                    .font(.headline)
                Text(locationText.isEmpty ? "-" : locationText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10))

            Spacer(minLength: 0)

            Button(action: onCreateAnother) {
                Text(language.t("landmark.createAnother"))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent)

            Button(action: onBack) {
                Text(language.t("landmark.backHome"))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
            }
            .buttonStyle(.bordered)
        }
        .padding(20)
    }
}
