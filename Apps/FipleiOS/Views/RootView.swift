import SwiftUI

/// Gates the app on pairing. First-run (never paired) shows the code-entry
/// screen. Once the phone has paired before, it always presents the tabbed
/// interface — even away from the Mac's network — so off-LAN Files access keeps
/// working while the Home/Recent tabs reconnect in the background.
struct RootView: View {
    let controller: RemoteController

    var body: some View {
        if controller.phase == .connected || controller.hasEverPaired {
            MainTabView(controller: controller)
        } else {
            PairingView(controller: controller)
        }
    }
}
