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
            .overlay(alignment: .bottom) {
                if let message = controller.runFailureMessage {
                    RunFailureToast(message: message) { controller.dismissRunFailure() }
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.spring(duration: 0.3), value: controller.runFailureMessage)
            .sensoryFeedback(.error, trigger: controller.runFailureMessage) { _, new in new != nil }
            .onChange(of: controller.runFailureMessage) { _, message in
                guard message != nil else { return }
                Task {
                    try? await Task.sleep(for: .seconds(4))
                    controller.dismissRunFailure()
                }
            }
            .onChange(of: controller.pairingRequested) { _, requested in
                // Explicit ask (Settings → Pair New Mac, or a first-run CTA)
                // overrides an earlier dismissal.
                guard requested else { return }
                userDismissedPairing = false
                showPairing = true
                controller.pairingRequested = false
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
            // First run with no Mac found yet (Mac app not running, other
            // network): pairing must still be reachable — PairingView holds a
            // typed code and pairs the moment a Mac appears. Without this, a
            // new user has no way into the pairing flow at all.
            if !controller.hasEverPaired && !userDismissedPairing { showPairing = true }
        }
    }
}

/// Transient bottom toast for launch failures — the only feedback channel for
/// "you tapped it, but nothing happened on the Mac".
private struct RunFailureToast: View {
    let message: String
    let onDismiss: () -> Void

    var body: some View {
        Button(action: onDismiss) {
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.orange)
                Text(message)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Theme.Palette.label)
                    .multilineTextAlignment(.leading)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(.ultraThinMaterial, in: Capsule())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 24)
        // Float clear of the floating tab bar, not behind it.
        .padding(.bottom, Theme.Spacing.tabBarClearance)
        .accessibilityLabel("Launch failed. \(message). Double tap to dismiss.")
    }
}
