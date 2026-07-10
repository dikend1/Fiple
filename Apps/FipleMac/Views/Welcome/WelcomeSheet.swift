import SwiftUI

/// First-launch welcome sheet: what Fiple is, how the phone connects, where
/// the tools live. One screen, three rows, one button — Apple's welcome-panel
/// pattern, matched to the app's light surface palette.
struct WelcomeSheet: View {
    let onFinish: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Image("FipleLogo")
                .resizable()
                .scaledToFit()
                .frame(width: 64, height: 64)
                .padding(.top, 36)

            Text("Welcome to Fiple")
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(.primary)
                .padding(.top, 16)
            Text("Your Mac, one tap from your iPhone.")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .padding(.top, 4)

            VStack(alignment: .leading, spacing: 22) {
                WelcomeRow(
                    icon: "square.grid.2x2.fill", tint: Theme.Palette.brand,
                    title: "Build workspaces",
                    detail: "Group apps, sites and files into tiles. Tapping one on the phone restores the whole context here."
                )
                WelcomeRow(
                    icon: "iphone", tint: Color(hex: "#2F6BFF"),
                    title: "Pair your iPhone",
                    detail: "Get Fiple on your iPhone, join the same Wi-Fi, and enter the 4-digit code from the Devices page."
                )
                WelcomeRow(
                    icon: "wrench.and.screwdriver.fill", tint: .orange,
                    title: "Tools",
                    detail: "A phone-side terminal and Smart Trash cleanup live in the sidebar — Terminal needs a master password first."
                )
            }
            .padding(.top, 30)
            .padding(.horizontal, 40)
            .frame(maxWidth: .infinity, alignment: .leading)

            Label {
                Text("Everything stays on your own Wi-Fi. No cloud, no accounts.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            } icon: {
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 28)

            Button(action: onFinish) {
                Text("Get Started")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 40)
                    .background(Theme.Palette.brand, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.defaultAction)
            .padding(.top, 20)
            .padding(.horizontal, 40)
            .padding(.bottom, 28)
        }
        .frame(width: 460)
        .background(Theme.Palette.surface)
    }
}

/// One welcome row: tinted SF symbol in a fixed column, title + detail.
private struct WelcomeRow: View {
    let icon: String
    let tint: Color
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(tint)
                .frame(width: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)
                Text(detail)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
