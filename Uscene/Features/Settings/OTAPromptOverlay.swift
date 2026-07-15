import SwiftUI

/// Shown after splash when `ota/latest` reports a needed or forced update.
struct OTAPromptOverlay: View {
    @Environment(LanguageManager.self) private var language

    let info: OTAInfo
    var onDismiss: () -> Void

    private var isForced: Bool {
        let raw = (info.force_update ?? "").lowercased()
        return raw == "1" || raw == "true" || raw == "yes"
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.45).ignoresSafeArea()
            VStack(alignment: .leading, spacing: 14) {
                Text(language.t("ota.title"))
                    .font(.title3.bold())
                if let version = info.version {
                    Text("\(language.t("ota.latest")): \(version)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                if let notes = info.release_notes, !notes.isEmpty {
                    Text(notes)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    Text(language.t("ota.needUpdate"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                if let urlString = info.download_url, let url = URL(string: urlString) {
                    Link(destination: url) {
                        Text(language.t("ota.openStore"))
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.accentColor)
                            .foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                }

                if !isForced {
                    Button(language.t("ota.later")) {
                        onDismiss()
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 4)
                }
            }
            .padding(20)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
            .padding(28)
        }
    }
}
