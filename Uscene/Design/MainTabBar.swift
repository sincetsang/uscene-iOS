import SwiftUI

enum AppTab: Int, CaseIterable, Hashable {
    case map, uai, shop, mine

    var titleKey: String {
        switch self {
        case .map: return "tabbar.map"
        case .uai: return "tabbar.uai"
        case .shop: return "tabbar.shop"
        case .mine: return "tabbar.mine"
        }
    }

    var iconNor: String {
        switch self {
        case .map: return "TabHomeNor"
        case .uai: return "TabUAINor"
        case .shop: return "TabShopNor"
        case .mine: return "TabMineNor"
        }
    }

    var iconSel: String {
        switch self {
        case .map: return "TabHomeSel"
        case .uai: return "TabUAISel"
        case .shop: return "TabShopSel"
        case .mine: return "TabMineSel"
        }
    }

    var iconSize: CGSize {
        switch self {
        case .uai: return CGSize(width: 28, height: 28)
        case .map: return CGSize(width: 22, height: 20)
        default: return CGSize(width: 22, height: 22)
        }
    }
}

struct MainTabBar: View {
    @Binding var selection: AppTab
    var mineBadge: Int = 0
    @Environment(LanguageManager.self) private var language

    var body: some View {
        VStack(spacing: 0) {
            Divider().overlay(Color.black.opacity(0.06))
            HStack(spacing: 0) {
                ForEach(AppTab.allCases, id: \.self) { tab in
                    Button {
                        selection = tab
                    } label: {
                        VStack(spacing: 4) {
                            ZStack(alignment: .topTrailing) {
                                Image(selection == tab ? tab.iconSel : tab.iconNor)
                                    .resizable()
                                    .renderingMode(.original)
                                    .scaledToFit()
                                    .frame(width: tab.iconSize.width, height: tab.iconSize.height)
                                    .offset(y: tab == .uai ? -2 : 0)

                                if tab == .mine, mineBadge > 0 {
                                    Circle()
                                        .fill(Color.red)
                                        .frame(width: 8, height: 8)
                                        .offset(x: 6, y: -2)
                                }
                            }
                            Text(language.t(tab.titleKey))
                                .font(.system(size: 12))
                                .foregroundStyle(selection == tab ? Theme.brand : Theme.text)
                                .offset(y: tab == .uai ? -2 : 0)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 8)
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(height: Theme.tabBarHeight)
            .background(Color.white)
        }
        .background(Color.white.ignoresSafeArea(edges: .bottom))
    }
}

extension View {
    /// Attach the custom tab bar to a tab's ROOT screen.
    /// Uses overlay + reserved bottom padding (not `safeAreaInset`) so push transitions
    /// don't reflow FAB/chrome upward when the tab bar leaves the hierarchy.
    ///
    /// Child views can set `HidesRootTabBarKey` (e.g. map recommend fullscreen)
    /// to slide the tab away like a pushed page — without using Navigation push.
    func rootTabBar(_ selection: Binding<AppTab>, badge: Int = 0) -> some View {
        modifier(RootTabBarModifier(selection: selection, badge: badge))
    }
}

/// Preferenced by map recommend (and similar) so the root tab bar can hide
/// while a home overlay goes true-fullscreen — same end state as a pushed page.
enum HidesRootTabBarKey: PreferenceKey {
    static var defaultValue = false
    static func reduce(value: inout Bool, nextValue: () -> Bool) {
        value = value || nextValue()
    }
}

private struct RootTabBarModifier: ViewModifier {
    @Binding var selection: AppTab
    var badge: Int
    @State private var hidden = false

    private static let hideSpring = Animation.interactiveSpring(response: 0.38, dampingFraction: 0.86)

    func body(content: Content) -> some View {
        content
            // When hidden (map recommend fullscreen), drop reserved space so the
            // home GeometryReader can grow to a true full-screen page.
            .safeAreaPadding(.bottom, hidden ? 0 : Theme.tabBarHeight)
            .overlay(alignment: .bottom) {
                MainTabBar(selection: $selection, mineBadge: badge)
                    .opacity(hidden ? 0 : 1)
                    .offset(y: hidden ? Theme.tabBarHeight + 8 : 0)
                    .allowsHitTesting(!hidden)
                    .accessibilityHidden(hidden)
            }
            .onPreferenceChange(HidesRootTabBarKey.self) { hidden = $0 }
            .animation(Self.hideSpring, value: hidden)
    }
}
