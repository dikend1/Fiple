import SwiftUI

/// First-launch welcome: one screen of what Fiple does, one screen of how to
/// connect. Follows Apple's own welcome-panel pattern — feature rows, a
/// privacy note, one big button — rather than a marketing carousel.
struct WelcomeView: View {
    let onFinish: () -> Void

    private enum Page { case features, connect }
    @State private var page: Page = .features

    init(onFinish: @escaping () -> Void) {
        self.onFinish = onFinish
        #if DEBUG
        // "-welcome-connect": open on the second page, for screenshots.
        if ProcessInfo.processInfo.arguments.contains("-welcome-connect") {
            _page = State(initialValue: .connect)
        }
        #endif
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                Group {
                    switch page {
                    case .features: featuresPage
                    case .connect: connectPage
                    }
                }
                .padding(.horizontal, 28)
                .padding(.top, 56)
                .frame(maxWidth: .infinity)
            }
            .scrollBounceBehavior(.basedOnSize)

            footer
                .padding(.horizontal, 28)
                .padding(.bottom, 12)
        }
        .background(Theme.Palette.background)
    }

    // MARK: - Page 1: what Fiple does

    private var featuresPage: some View {
        VStack(spacing: 0) {
            Image("FipleLogo")
                .resizable()
                .scaledToFit()
                .frame(width: 76, height: 76)

            Text("Welcome to Fiple")
                .font(.fiple(30, .bold))
                .foregroundStyle(Theme.Palette.label)
                .padding(.top, 20)
            Text("Your Mac, one tap from your iPhone.")
                .font(.fiple(16))
                .foregroundStyle(Theme.Palette.secondary)
                .padding(.top, 4)

            VStack(alignment: .leading, spacing: 26) {
                FeatureRow(
                    icon: "square.grid.2x2.fill", tint: Theme.Palette.brand,
                    title: "Workspaces",
                    detail: "Tap a tile to open your apps, sites and files on the Mac — your whole working context at once."
                )
                FeatureRow(
                    icon: "terminal.fill", tint: Color(hex: "#0E1116"),
                    title: "Terminal",
                    detail: "A real shell on your Mac, locked behind your master password and Face ID."
                )
                FeatureRow(
                    icon: "square.and.arrow.up.fill", tint: Theme.Palette.brandLink,
                    title: "Send to Mac",
                    detail: "Beam photos and files straight into Downloads — images land on the Mac's clipboard too."
                )
                FeatureRow(
                    icon: "trash.fill", tint: .orange,
                    title: "Smart Trash",
                    detail: "Review stale files from your phone and free up space on the Mac."
                )
            }
            .padding(.top, 36)
            .frame(maxWidth: .infinity, alignment: .leading)

            Label {
                Text("Fiple works over your own Wi-Fi. No cloud, no accounts — your iPhone and Mac talk directly.")
                    .font(.fiple(12))
                    .foregroundStyle(Theme.Palette.secondary)
            } icon: {
                Image(systemName: "lock.shield.fill")
                    .font(.fiple(15))
                    .foregroundStyle(Theme.Palette.secondary)
            }
            .padding(.top, 36)
            .padding(.bottom, 16)
        }
    }

    // MARK: - Page 2: how to connect

    private var connectPage: some View {
        VStack(spacing: 0) {
            Image(systemName: "macbook.and.iphone")
                .font(.system(size: 52, weight: .regular))
                .foregroundStyle(Theme.Palette.brand)
                .frame(height: 76)

            Text("Connect Your Mac")
                .font(.fiple(30, .bold))
                .foregroundStyle(Theme.Palette.label)
                .padding(.top, 20)
            Text("Three steps, about a minute.")
                .font(.fiple(16))
                .foregroundStyle(Theme.Palette.secondary)
                .padding(.top, 4)

            VStack(alignment: .leading, spacing: 26) {
                StepRow(
                    number: 1, title: "Open Fiple on your Mac",
                    detail: "Install the Mac app and launch it — it lives in the menu bar."
                )
                StepRow(
                    number: 2, title: "Join the same Wi-Fi",
                    detail: "Your iPhone and Mac must be on the same network."
                )
                StepRow(
                    number: 3, title: "Enter the pairing code",
                    detail: "Type the 4-digit code from the Mac's Devices page. That's it."
                )
            }
            .padding(.top, 36)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Footer button

    private var footer: some View {
        Button {
            switch page {
            case .features:
                withAnimation(.snappy) { page = .connect }
            case .connect:
                onFinish()
            }
        } label: {
            Text(page == .features ? "Continue" : "Get Started")
                .font(.fiple(17, .semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(Theme.Palette.brand, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .padding(.top, 8)
    }
}

/// One welcome feature: tinted SF symbol in a fixed column, title + detail.
private struct FeatureRow: View {
    let icon: String
    let tint: Color
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 26, weight: .medium))
                .foregroundStyle(tint)
                .frame(width: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.fiple(16, .semibold))
                    .foregroundStyle(Theme.Palette.label)
                Text(detail)
                    .font(.fiple(14))
                    .foregroundStyle(Theme.Palette.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// One setup step: numbered badge, title + detail.
private struct StepRow: View {
    let number: Int
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Text("\(number)")
                .font(.fiple(16, .bold))
                .foregroundStyle(Theme.Palette.brand)
                .frame(width: 32, height: 32)
                .background(Theme.Palette.brand.opacity(0.12), in: Circle())
                .frame(width: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.fiple(16, .semibold))
                    .foregroundStyle(Theme.Palette.label)
                Text(detail)
                    .font(.fiple(14))
                    .foregroundStyle(Theme.Palette.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
