import SwiftUI

struct RootView: View {
    let controller: RemoteController

    var body: some View {
        switch controller.phase {
        case .searching, .readyToPair, .connecting:
            PairingView(controller: controller)
        case .connected:
            TileGridView(controller: controller)
        }
    }
}
