import FipleKit
import SwiftUI
import UIKit

/// The tabbed interface is **always** shown — pairing never gates the whole app
/// (Recent and Settings remain browsable off-network). Code entry is a
/// dismissible sheet that appears when a Mac is found on the network and closes
/// itself once paired; the user can swipe it away and come back later.
struct RootView: View {
    let controller: RemoteController

    @State private var showPairing = false
    /// Set when the user dismisses the pairing sheet, so it doesn't immediately
    /// reappear while the Mac is still discoverable. Reset once connected.
    @State private var userDismissedPairing = false

    /// One-time welcome on first launch; the pairing sheet holds back until
    /// it's dismissed so the two presentations never fight.
    @AppStorage("fiple.hasSeenWelcome") private var hasSeenWelcome = false
    @State private var showWelcome = false

    var body: some View {
        MainTabView(controller: controller)
            .overlay { GestureOverlay(onGesture: handleGesture) }
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
            .fullScreenCover(isPresented: $showWelcome, onDismiss: {
                // Now that welcome is out of the way, let pairing appear.
                syncPairingSheet(controller.phase)
            }) {
                WelcomeView {
                    hasSeenWelcome = true
                    showWelcome = false
                }
            }
            .onAppear {
                #if DEBUG
                // "-welcome": force the first-run welcome, for screenshots.
                if ProcessInfo.processInfo.arguments.contains("-welcome") { showWelcome = true }
                #endif
                if !hasSeenWelcome { showWelcome = true }
                syncPairingSheet(controller.phase)
            }
            .onChange(of: controller.phase) { _, phase in syncPairingSheet(phase) }
            #if DEBUG
            .onChange(of: controller.replayWelcomeRequested) { _, requested in
                guard requested else { return }
                controller.replayWelcomeRequested = false
                showWelcome = true
            }
            #endif
    }

    /// A recognized global gesture: give immediate haptic feedback, then (if a
    /// Mac is connected) send it. The "declined" tap when nothing is connected
    /// keeps the gesture from feeling broken/silent.
    private func handleGesture(_ action: GestureAction) {
        guard controller.isConnected else {
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
            return
        }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        Task { await controller.sendGesture(action) }
    }

    private func syncPairingSheet(_ phase: RemoteController.Phase) {
        // Welcome owns the screen on first launch; pairing shows on dismiss.
        guard !showWelcome else { return }
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
