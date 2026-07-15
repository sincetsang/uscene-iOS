import SwiftUI
import PhotosUI
import UIKit

struct ProfileEditView: View {
    @Environment(LanguageManager.self) private var language
    @Environment(AuthStore.self) private var auth

    @State private var nickname = ""
    @State private var bio = ""
    @State private var avatarURL = ""
    @State private var pickerItem: PhotosPickerItem?
    @State private var previewImage: UIImage?
    @State private var isSaving = false
    @State private var isUploading = false
    @State private var message: String?
    @State private var errorMessage: String?

    var body: some View {
        Form {
            Section(language.t("mine.avatar")) {
                HStack {
                    Spacer()
                    ZStack(alignment: .bottomTrailing) {
                        Group {
                            if let previewImage {
                                Image(uiImage: previewImage)
                                    .resizable()
                                    .scaledToFill()
                            } else {
                                AsyncImage(url: URL(string: avatarURL)) { phase in
                                    switch phase {
                                    case .success(let image): image.resizable().scaledToFill()
                                    default: Image("DefaultAvatar").resizable().scaledToFill()
                                    }
                                }
                            }
                        }
                        .frame(width: 88, height: 88)
                        .clipShape(Circle())

                        PhotosPicker(selection: $pickerItem, matching: .images) {
                            Image(systemName: "camera.fill")
                                .font(.caption)
                                .padding(6)
                                .background(.ultraThinMaterial, in: Circle())
                        }
                    }
                    Spacer()
                }
                .onChange(of: pickerItem) { _, item in
                    Task { await uploadAvatar(item) }
                }
                if isUploading {
                    ProgressView(language.t("common.loading"))
                }
            }

            Section {
                TextField(language.t("mine.nickname"), text: $nickname)
                TextField(language.t("mine.bio"), text: $bio, axis: .vertical)
                    .lineLimit(3...5)
                HStack {
                    Text("ID")
                    Spacer()
                    Text("\(auth.user?.user_id ?? auth.user?.id ?? 0)")
                        .foregroundStyle(.secondary)
                }
                if let code = auth.user?.invite_code, !code.isEmpty {
                    HStack {
                        Text(language.t("mine.inviteCode"))
                        Spacer()
                        Text(code).foregroundStyle(.secondary)
                        Button(language.t("common.copy")) {
                            UIPasteboard.general.string = code
                            message = language.t("common.copied")
                        }
                    }
                }
                if let level = auth.user?.level {
                    HStack {
                        Text(language.t("mine.level"))
                        Spacer()
                        Text("Lv.\(level)").foregroundStyle(.secondary)
                    }
                }
            }

            if !auth.auths.isEmpty {
                Section(language.t("mine.linkedAccounts")) {
                    ForEach(auth.auths) { binding in
                        HStack {
                            Text(providerTitle(binding.provider))
                            Spacer()
                            Text(binding.external_id ?? "-")
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
            }

            if let message {
                Section { Text(message).foregroundStyle(.secondary) }
            }
            if let errorMessage {
                Section { Text(errorMessage).foregroundStyle(.red) }
            }

            Section {
                Button {
                    Task { await save() }
                } label: {
                    if isSaving {
                        ProgressView().frame(maxWidth: .infinity)
                    } else {
                        Text(language.t("common.done")).frame(maxWidth: .infinity)
                    }
                }
                .disabled(isSaving || isUploading || nickname.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .navigationTitle(language.t("mine.editInformation"))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            nickname = auth.user?.nickname ?? ""
            bio = auth.user?.profileDescription ?? ""
            avatarURL = auth.user?.avatar_url ?? ""
        }
    }

    private func providerTitle(_ provider: String?) -> String {
        switch (provider ?? "").lowercased() {
        case "apple": return language.t("login.apple")
        case "google": return language.t("login.google")
        case "email": return language.t("login.email")
        case "phone": return language.t("login.phone")
        default: return provider ?? language.t("mine.linkedAccounts")
        }
    }

    @MainActor
    private func uploadAvatar(_ item: PhotosPickerItem?) async {
        guard let item else { return }
        isUploading = true
        errorMessage = nil
        defer { isUploading = false }
        do {
            guard let data = try await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: data) else {
                throw APIError.emptyData
            }
            previewImage = image
            avatarURL = try await CheckinAPI.uploadImage(image)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func save() async {
        isSaving = true
        message = nil
        errorMessage = nil
        defer { isSaving = false }
        do {
            try await UserAPI.updateProfile(
                nickname: nickname.trimmingCharacters(in: .whitespacesAndNewlines),
                avatarURL: avatarURL
            )
            try await UserAPI.updateDescription(bio.trimmingCharacters(in: .whitespacesAndNewlines))
            try await auth.refreshUser()
            message = language.t("mine.updateSuccess")
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
