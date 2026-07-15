import SwiftUI
import UIKit

enum Theme {
    static let brand = Color("BrandPrimary")
    static let text = Color("TextPrimary")
    static let link = Color("LinkBlue")
    static let shop = Color("ShopBlue")
    static let shopBar = Color("ShopBar")
    static let uaiWash = Color("UAIWash")
    static let inputBorder = Color("InputBorder")
    static let sheetHandle = Color("SheetHandle")
    static let chipFill = Color("ChipFill")

    static let tabBarHeight: CGFloat = 52
    static let mapSheetCollapsed: CGFloat = 250

    /// Status-bar / Dynamic Island inset from the key window.
    /// Prefer this over `safeAreaPadding` after `ignoresSafeArea(edges: .top)`
    /// (which zeroes out SwiftUI's reported safe-area padding).
    static var topSafeAreaInset: CGFloat {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let windows = scenes.flatMap(\.windows)
        let window = windows.first(where: \.isKeyWindow) ?? windows.first
        return window?.safeAreaInsets.top ?? 59
    }

    /// Full key-window height (for map recommend expanding to a true page).
    static var windowHeight: CGFloat {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let windows = scenes.flatMap(\.windows)
        let window = windows.first(where: \.isKeyWindow) ?? windows.first
        return window?.bounds.height ?? UIScreen.main.bounds.height
    }

    /// Match RN `formatDistance`: meters under 1km as `Xm`, otherwise `X.Xkm`.
    static func formatDistance(_ meters: Double) -> String {
        if meters < 1000 {
            return String(format: "%.0fm", meters)
        }
        return String(format: "%.1fkm", meters / 1000)
    }
}

extension View {
    /// Tab home pages: hide NavigationStack chrome and draw from the physical top.
    func tabRootChrome() -> some View {
        self
            .toolbar(.hidden, for: .navigationBar)
            .toolbarBackground(.hidden, for: .navigationBar)
            .ignoresSafeArea(edges: .top)
    }

    /// Keep custom header / title below the status bar or Dynamic Island.
    func tabRootHeaderInset(_ extra: CGFloat = 0) -> some View {
        padding(.top, Theme.topSafeAreaInset + extra)
    }
}
