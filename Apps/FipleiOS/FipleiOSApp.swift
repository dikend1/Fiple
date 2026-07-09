import SwiftUI

@main
struct FipleiOSApp: App {
    @State private var controller = RemoteController()

    var body: some Scene {
        WindowGroup {
            RootView(controller: controller)
                .preferredColorScheme(.light) // app uses a fixed light palette; lock the
                                              // scheme so dark-mode devices don't render
                                              // adaptive text (section headers, tab labels) white.
                .task { controller.begin() }
        }
    }
}
