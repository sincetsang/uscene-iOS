import SwiftUI

@main
struct UsceneApp: App {
    @State private var auth = AuthStore.shared
    @State private var language = LanguageManager.shared
    @State private var location = LocationManager.shared
    @State private var showSplash = true
    @State private var showOnboarding = OnboardingStore.needsOnboarding
    @State private var pendingOTA: OTAInfo?

    var body: some Scene {
        WindowGroup {
            ZStack {
                RootView()
                    .tint(Color(red: 0, green: 0.482, blue: 0.996))
                    .opacity(showSplash || showOnboarding ? 0 : 1)

                if showSplash {
                    SplashView()
                        .transition(.opacity)
                } else if showOnboarding {
                    OnboardingGuideView {
                        OnboardingStore.markCompleted()
                        withAnimation(.easeOut(duration: 0.3)) {
                            showOnboarding = false
                        }
                    }
                    .transition(.opacity)
                    .zIndex(1)
                }

                if !showSplash, !showOnboarding, let pendingOTA {
                    OTAPromptOverlay(info: pendingOTA) {
                        self.pendingOTA = nil
                    }
                    .transition(.opacity)
                    .zIndex(2)
                }
            }
            .environment(auth)
            .environment(language)
            .environment(location)
            .onOpenURL { url in
                WalletConnectBootstrap.handle(url: url)
                _ = UEPayBridge.shared.handleOpenURL(url)
            }
            .task {
                WalletConnectBootstrap.configureIfNeeded()
                UEPayBridge.shared.configure()
                location.requestPermissionAndLocate()
                await auth.bootstrap()
                async let otaTask = SystemAPI.otaLatest()
                try? await Task.sleep(nanoseconds: 900_000_000)
                withAnimation(.easeOut(duration: 0.35)) {
                    showSplash = false
                }
                if !showOnboarding, let ota = try? await otaTask, ota.need_update == true {
                    withAnimation {
                        pendingOTA = ota
                    }
                }
            }
            .onChange(of: showOnboarding) { _, isShowing in
                guard !isShowing else { return }
                Task {
                    if let ota = try? await SystemAPI.otaLatest(), ota.need_update == true {
                        withAnimation { pendingOTA = ota }
                    }
                }
            }
        }
    }
}
