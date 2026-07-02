import SwiftUI

/// The tabbed interface is **always** shown — Files works over iCloud without any
/// LAN pairing, so pairing must never gate the whole app. Code entry is a
/// dismissible sheet that appears when a Mac is found on the network and closes
/// itself once paired; the user can swipe it away to use Files instead.
struct RootView: View {
    let controller: RemoteController

    @State private var showPairing = false
    /// Set when the user dismisses the pairing sheet, so it doesn't immediately
    /// reappear while the Mac is still discoverable. Reset once connected.
    @State private var userDismissedPairing = false

    var body: some View {
        MainTabView(controller: controller)
            .sheet(isPresented: $showPairing, onDismiss: {
                if controller.phase != .connected { userDismissedPairing = true }
            }) {
                PairingView(controller: controller)
                    .overlay(alignment: .topTrailing) {
                        Button {
                            userDismissedPairing = true
                            showPairing = false
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 28))
                                .foregroundStyle(Theme.Palette.secondary.opacity(0.5))
                                .padding()
                        }
                        .accessibilityLabel("Close")
                    }
            }
            .onAppear { syncPairingSheet(controller.phase) }
            .onChange(of: controller.phase) { _, phase in syncPairingSheet(phase) }
    }

    private func syncPairingSheet(_ phase: RemoteController.Phase) {
        switch phase {
        case .readyToPair, .connecting:
            if !userDismissedPairing { showPairing = true }
        case .connected:
            showPairing = false
            userDismissedPairing = false
        case .searching:
            break
        }
    }
}
