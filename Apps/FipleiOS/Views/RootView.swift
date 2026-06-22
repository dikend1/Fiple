import SwiftUI

/// Gates the app on pairing: until a Mac is connected the remote shows the
/// code-entry screen; once paired it presents the four-tab interface.
struct RootView: View {
    let controller: RemoteController

    var body: some View {
        switch controller.phase {
        case .searching, .readyToPair, .connecting:
            PairingView(controller: controller)
        case .connected:
            MainTabView(controller: controller)
        }
    }
}
