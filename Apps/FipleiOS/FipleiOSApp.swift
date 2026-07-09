import SwiftUI

@main
struct FipleiOSApp: App {
    @State private var controller = RemoteController()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView(controller: controller)
                .preferredColorScheme(.light) // app uses a fixed light palette; lock the
                                              // scheme so dark-mode devices don't render
                                              // adaptive text (section headers, tab labels) white.
                .task { controller.begin() }
                // Copy something on the phone (a screenshot via Copy, text, a
                // photo), switch to Fiple — it lands on the Mac's clipboard by
                // itself, ready to ⌘V. iOS may show its "Allow Paste" prompt;
                // "Paste from Other Apps: Allow" in the system app settings
                // silences it for good.
                .onChange(of: scenePhase) { _, phase in
                    guard phase == .active else { return }
                    Task { await controller.syncClipboardToMacIfNew() }
                }
        }
    }
}
