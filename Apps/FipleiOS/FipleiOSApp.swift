import SwiftUI

@main
struct FipleiOSApp: App {
    @State private var controller = RemoteController()

    var body: some Scene {
        WindowGroup {
            RootView(controller: controller)
                .task { controller.begin() }
        }
    }
}
