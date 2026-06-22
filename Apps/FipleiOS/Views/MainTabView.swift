import SwiftUI

/// Root of the remote: four flat sections in a tab bar, matching the mockups.
/// Each tab owns its own `NavigationStack`. Screens are presentation-only and
/// run on sample data until the real device/session logic is wired up.
struct MainTabView: View {
    let controller: RemoteController

    enum Tab: Hashable { case home, focus, recent, settings }

    @State private var selection: Tab = .home

    var body: some View {
        TabView(selection: $selection) {
            HomeView(controller: controller) { selection = .settings }
                .tag(Tab.home)
                .tabItem { Label("Home", systemImage: "house.fill") }

            FocusListView()
                .tag(Tab.focus)
                .tabItem { Label("Focus", systemImage: "circle.circle.fill") }

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
