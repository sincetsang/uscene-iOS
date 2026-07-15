import SwiftUI

struct LandmarkReportView: View {
    @Environment(LanguageManager.self) private var language
    @Environment(\.dismiss) private var dismiss

    let spotId: Int

    @State private var types: [ComplaintType] = []
    @State private var selectedType: ComplaintType?
    @State private var content = ""
    @State private var isLoading = false
    @State private var isSubmitting = false
    @State private var errorMessage: String?
    @State private var didSubmit = false

    var body: some View {
        Form {
            Section(language.t("report.type")) {
                if isLoading && types.isEmpty {
                    ProgressView()
                } else {
                    Picker(language.t("report.type"), selection: $selectedType) {
                        Text("-").tag(ComplaintType?.none)
                        ForEach(types) { type in
                            Text(type.displayName).tag(Optional(type))
                        }
                    }
                }
            }
            Section(language.t("report.content")) {
                TextField(language.t("report.content"), text: $content, axis: .vertical)
                    .lineLimit(3...6)
            }
            if let errorMessage {
                Section { Text(errorMessage).foregroundStyle(.red) }
            }
            if didSubmit {
                Section { Text(language.t("report.success")).foregroundStyle(.green) }
            }
        }
        .navigationTitle(language.t("report.title"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(language.t("common.done")) {
                    Task { await submit() }
                }
                .disabled(isSubmitting)
            }
        }
        .task { await load() }
    }

    @MainActor
    private func load() async {
        isLoading = true
        defer { isLoading = false }
        types = (try? await SystemAPI.complaintTypes()) ?? []
    }

    @MainActor
    private func submit() async {
        errorMessage = nil
        guard let type = selectedType?.type ?? selectedType?.id, !type.isEmpty else {
            errorMessage = language.t("report.requireType")
            return
        }
        isSubmitting = true
        defer { isSubmitting = false }
        do {
            try await SystemAPI.reportSpot(spotId: spotId, type: type, content: content)
            didSubmit = true
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
