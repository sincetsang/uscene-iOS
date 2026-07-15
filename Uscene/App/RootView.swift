import SwiftUI

struct RootView: View {
    @Environment(LanguageManager.self) private var language
    @Environment(AuthStore.self) private var auth
    @State private var unreadCount = 0
    @State private var selectedTab: AppTab = .map

    var body: some View {
        Group {
            // Tab bar lives inside each stack's ROOT view (via safeAreaInset), so pushing a
            // secondary page slides it away with the home view — like a native TabView.
            switch selectedTab {
            case .map:
                NavigationStack { MapHomeView().rootTabBar($selectedTab, badge: unreadCount) }
            case .uai:
                NavigationStack { UAIHomeView().rootTabBar($selectedTab, badge: unreadCount) }
            case .shop:
                NavigationStack { ShopHomeView().rootTabBar($selectedTab, badge: unreadCount) }
            case .mine:
                NavigationStack { MineView(unreadCount: unreadCount).rootTabBar($selectedTab, badge: unreadCount) }
            }
        }
        .ignoresSafeArea(.keyboard)
        .task(id: auth.isLoggedIn) {
            guard auth.isLoggedIn else {
                unreadCount = 0
                return
            }
            unreadCount = (try? await MessageAPI.unreadCount()) ?? 0
        }
    }
}
