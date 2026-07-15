import SwiftUI

struct LandmarkLicenseView: View {
    @Environment(LanguageManager.self) private var language

    let point: SpotPoint
    var coverURL: String?

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.09, green: 0.36, blue: 1.0),
                    Color(red: 0.12, green: 0.18, blue: 0.35)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 16) {
                Text(language.t("license.title"))
                    .font(.largeTitle.bold())
                    .foregroundStyle(.white)
                Text(language.t("license.desc"))
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.85))

                VStack(spacing: 0) {
                    Text(point.displayTitle)
                        .font(.title2.weight(.semibold))
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color(red: 0.94, green: 0.96, blue: 1.0))

                    AsyncImage(url: URL(string: coverURL ?? point.displayImage ?? "")) { phase in
                        switch phase {
                        case .success(let image):
                            image.resizable().scaledToFill()
                        default:
                            Color.gray.opacity(0.15)
                        }
                    }
                    .frame(width: 200, height: 200)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .padding(.top, 24)

                    VStack(spacing: 10) {
                        Text(language.t("license.owner"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(point.owner_username ?? language.t("license.official"))
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(Color.accentColor)
                            .lineLimit(1)

                        if let location = point.location, !location.isEmpty {
                            Text(location)
                                .font(.footnote)
                                .foregroundStyle(.primary)
                                .multilineTextAlignment(.center)
                                .padding(12)
                                .frame(maxWidth: .infinity)
                                .background(Color(red: 0.94, green: 0.96, blue: 1.0), in: RoundedRectangle(cornerRadius: 8))
                        }
                    }
                    .padding(20)
                }
                .background(.white, in: RoundedRectangle(cornerRadius: 16))
                .padding(.top, 24)

                Spacer()
            }
            .padding(20)
        }
        .navigationTitle(language.t("license.nav"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
    }
}
