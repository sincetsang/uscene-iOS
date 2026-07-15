import SwiftUI

struct MyAddressView: View {
    @Environment(LanguageManager.self) private var language
    @Environment(AuthStore.self) private var auth

    var selectionHandler: ((UserAddress) -> Void)? = nil

    @State private var addresses: [UserAddress] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showLogin = false
    @State private var editing: UserAddress?
    @State private var showEditor = false

    var body: some View {
        Group {
            if !auth.isLoggedIn {
                ContentUnavailableView {
                    Label(language.t("login.pleaseLogin"), systemImage: "mappin.circle")
                } actions: {
                    Button(language.t("login.signIn")) { showLogin = true }
                }
            } else if isLoading && addresses.isEmpty {
                ProgressView(language.t("common.loading"))
            } else if let errorMessage, addresses.isEmpty {
                ContentUnavailableView(language.t("common.error"), systemImage: "exclamationmark.triangle", description: Text(errorMessage))
            } else if addresses.isEmpty {
                ContentUnavailableView(language.t("address.empty"), systemImage: "mappin.slash")
            } else {
                List(addresses) { address in
                    Button {
                        if let selectionHandler {
                            selectionHandler(address)
                        } else {
                            editing = address
                            showEditor = true
                        }
                    } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(address.contactLine)
                                    .font(.headline)
                                    .foregroundStyle(.primary)
                                if address.isDefault {
                                    Text(language.t("address.default"))
                                        .font(.caption2.weight(.semibold))
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color.accentColor.opacity(0.15), in: Capsule())
                                        .foregroundStyle(Color.accentColor)
                                }
                            }
                            Text(address.fullAddress)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        if selectionHandler == nil {
                            Button(role: .destructive) {
                                Task { await delete(address) }
                            } label: {
                                Label(language.t("common.delete"), systemImage: "trash")
                            }
                            Button {
                                editing = address
                                showEditor = true
                            } label: {
                                Label(language.t("common.edit"), systemImage: "pencil")
                            }
                            .tint(.blue)
                        }
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
        .navigationTitle(language.t("address.title"))
        .toolbar {
            if selectionHandler == nil {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        editing = nil
                        showEditor = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .disabled(!auth.isLoggedIn)
                }
            }
        }
        .sheet(isPresented: $showLogin) { NavigationStack { LoginView() } }
        .sheet(isPresented: $showEditor) {
            NavigationStack {
                AddressEditView(address: editing) {
                    showEditor = false
                    Task { await load() }
                }
            }
        }
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
            addresses = try await CommerceAPI.addressList()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func delete(_ address: UserAddress) async {
        guard let id = address.address_id ?? Optional(address.id) else { return }
        do {
            try await CommerceAPI.deleteAddress(addressId: id)
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct AddressEditView: View {
    @Environment(LanguageManager.self) private var language
    @Environment(\.dismiss) private var dismiss

    let address: UserAddress?
    var onSaved: () -> Void

    @State private var name = ""
    @State private var phone = ""
    @State private var area = ""
    @State private var detail = ""
    @State private var isDefault = false
    @State private var isSubmitting = false
    @State private var errorMessage: String?
    @State private var showMapPicker = false

    var body: some View {
        Form {
            Section {
                TextField(language.t("shop.contactName"), text: $name)
                TextField(language.t("shop.contactPhone"), text: $phone)
                    .keyboardType(.phonePad)
                TextField(language.t("address.area"), text: $area)
                TextField(language.t("shop.contactAddress"), text: $detail, axis: .vertical)
                    .lineLimit(2...4)
                Button {
                    showMapPicker = true
                } label: {
                    Label(language.t("address.mapPick"), systemImage: "map")
                }
                Toggle(language.t("address.setDefault"), isOn: $isDefault)
            }
            if let errorMessage {
                Section { Text(errorMessage).foregroundStyle(.red) }
            }
        }
        .navigationTitle(address == nil ? language.t("address.add") : language.t("address.edit"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(language.t("common.cancel")) { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button(language.t("common.done")) {
                    Task { await save() }
                }
                .disabled(isSubmitting)
            }
        }
        .sheet(isPresented: $showMapPicker) {
            NavigationStack {
                AddressMapPickerView { pickedArea, pickedAddress, _ in
                    if !pickedArea.isEmpty { area = pickedArea }
                    if !pickedAddress.isEmpty { detail = pickedAddress }
                }
            }
        }
        .onAppear {
            name = address?.name ?? ""
            phone = address?.phone ?? ""
            area = address?.area ?? ""
            detail = address?.address ?? ""
            isDefault = address?.isDefault ?? false
        }
    }

    @MainActor
    private func save() async {
        errorMessage = nil
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty,
              !phone.trimmingCharacters(in: .whitespaces).isEmpty,
              !detail.trimmingCharacters(in: .whitespaces).isEmpty else {
            errorMessage = language.t("shop.requireAddress")
            return
        }
        isSubmitting = true
        defer { isSubmitting = false }
        let body = UpsertAddressBody(
            address_id: address?.address_id,
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            phone: phone.trimmingCharacters(in: .whitespacesAndNewlines),
            area: area.trimmingCharacters(in: .whitespacesAndNewlines),
            address: detail.trimmingCharacters(in: .whitespacesAndNewlines),
            is_default: isDefault ? 1 : 0
        )
        do {
            if address?.address_id != nil {
                try await CommerceAPI.updateAddress(body)
            } else {
                try await CommerceAPI.addAddress(body)
            }
            onSaved()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
