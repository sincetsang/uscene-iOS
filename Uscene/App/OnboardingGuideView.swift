import SwiftUI

/// First-install (or version-upgrade) walkthrough — matches RN `app/index.tsx` guide slides.
struct OnboardingGuideView: View {
    @Environment(LanguageManager.self) private var language
    var onFinished: () -> Void

    @State private var page = 0

    private let pages = ["Guide1", "Guide2", "Guide3"]

    var body: some View {
        ZStack {
            TabView(selection: $page) {
                ForEach(Array(pages.enumerated()), id: \.offset) { index, name in
                    Image(name)
                        .resizable()
                        .scaledToFill()
                        .ignoresSafeArea()
                        .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .ignoresSafeArea()

            if page == pages.count - 1 {
                VStack {
                    Spacer()
                    Button(action: onFinished) {
                        Text("\(language.t("home.start")) →")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 48)
                            .background(Theme.brand, in: Capsule())
                    }
                    .padding(.horizontal, 28)
                    .padding(.bottom, 70)
                }
            }
        }
        .background(Color.white.ignoresSafeArea())
    }
}

enum OnboardingStore {
    private static let buildKey = "key-buildnumber"

    static var needsOnboarding: Bool {
        let seen = UserDefaults.standard.string(forKey: buildKey)
        return seen != AppConfig.appVersion
    }

    static func markCompleted() {
        UserDefaults.standard.set(AppConfig.appVersion, forKey: buildKey)
    }
}
