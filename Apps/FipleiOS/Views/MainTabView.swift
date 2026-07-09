import FipleKit
import SwiftUI

/// Root of the remote: flat sections in a tab bar. Each tab owns its own
/// `NavigationStack`. Home / Recent / Settings are driven by the live
/// `RemoteController`.
struct MainTabView: View {
    let controller: RemoteController

    enum Tab: Hashable { case home, recent, settings }

    @State private var selection: Tab = .home

    var body: some View {
        // App Store-style bar on iOS 26: shrinks to a compact pill while
        // scrolling down, expands again on scroll-up. Earlier iOS keeps the
        // standard bar.
        if #available(iOS 26.0, *) {
            tabs.tabBarMinimizeBehavior(.onScrollDown)
        } else {
            tabs
        }
    }

    private var tabs: some View {
        TabView(selection: $selection) {
            HomeView(
                controller: controller,
                onOpenSettings: { selection = .settings }
            )
            .tag(Tab.home)
            .tabItem { Label("Home", systemImage: "house.fill") }

            RecentView(controller: controller)
                .tag(Tab.recent)
                .tabItem { Label("Recent", systemImage: "clock.fill") }

            SettingsView(controller: controller)
                .tag(Tab.settings)
                .tabItem { Label("Settings", systemImage: "gearshape.fill") }
        }
        .tint(Theme.Palette.brand)
    }
}
