import SwiftUI

/// Root of the remote: flat sections in a tab bar. Each tab owns its own
/// `NavigationStack`. Home / Recent / Settings are driven by the live
/// `RemoteController`.
struct MainTabView: View {
    let controller: RemoteController

    enum Tab: Hashable { case home, files, recent, settings }

    @State private var selection: Tab = .home

    var body: some View {
        TabView(selection: $selection) {
            HomeView(controller: controller) { selection = .settings }
                .tag(Tab.home)
                .tabItem { Label("Home", systemImage: "house.fill") }

            FilesView()
                .tag(Tab.files)
                .tabItem { Label("Files", systemImage: "folder.fill") }

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
