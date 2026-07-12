import SwiftUI

extension Notification.Name {
    /// Posted by Settings → Show Welcome Guide; MainWindowView re-opens the sheet.
    static let fipleReplayWelcome = Notification.Name("fiple.replayWelcome")
}

/// First-launch onboarding sheet: a paged, illustrated walkthrough matched to
/// the app's light window — each step has a composed hero graphic (not a text
/// row), Back/Continue navigation, and page dots. Ends on the pairing guide.
struct WelcomeSheet: View {
    let onFinish: () -> Void

    @State private var page = 0
    private let pageCount = 5
    private var isLast: Bool { page == pageCount - 1 }

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                switch page {
                case 0: welcomePage
                case 1:
                    FeatureStep(hero: { WorkspacesHeroMac() },
                                title: "Build workspaces",
                                subtitle: "Group apps, sites and files into a tile. Tapping it on the phone restores the whole context here.")
                case 2:
                    FeatureStep(hero: { TerminalHeroMac() },
                                title: "Terminal & tools",
                                subtitle: "Your phone gets a real shell on this Mac (behind a master password) plus Smart Trash cleanup — in the sidebar.")
                case 3:
                    FeatureStep(hero: { BeamHeroMac() },
                                title: "Send to this Mac",
                                subtitle: "Photos and files beamed from your phone land in Downloads — images on the clipboard too.")
                default: connectPage
                }
            }
            .frame(height: 300)
            .transition(.asymmetric(
                insertion: .opacity.combined(with: .offset(x: 30)),
                removal: .opacity.combined(with: .offset(x: -30))
            ))
            .id(page)
            .animation(.snappy, value: page)

            Divider()

            footer
        }
        .frame(width: 480)
        .background(Theme.Palette.surface)
    }

    // MARK: Pages

    private var welcomePage: some View {
        VStack(spacing: 0) {
            Image("FipleLogo")
                .resizable().scaledToFit()
                .frame(width: 72, height: 72)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .shadow(color: Theme.Palette.brand.opacity(0.25), radius: 18, y: 8)
                .padding(.top, 44)
            Text("Welcome to Fiple")
                .font(.system(size: 26, weight: .bold))
                .padding(.top, 22)
            Text("Your Mac, one tap from your iPhone.")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .padding(.top, 5)
            Spacer(minLength: 0)
            Label {
                Text("Everything stays on your own Wi-Fi. No cloud, no accounts.")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            } icon: {
                Image(systemName: "lock.shield.fill").font(.system(size: 12)).foregroundStyle(Theme.Palette.brand)
            }
            .padding(.bottom, 24)
        }
    }

    private var connectPage: some View {
        VStack(spacing: 0) {
            Image(systemName: "iphone.gen3.radiowaves.left.and.right")
                .font(.system(size: 44))
                .foregroundStyle(Theme.Palette.brand)
                .padding(.top, 30)
            Text("Pair your iPhone")
                .font(.system(size: 22, weight: .bold))
                .padding(.top, 16)

            VStack(alignment: .leading, spacing: 16) {
                StepRowMac(number: 1, title: "Get Fiple on your iPhone",
                           detail: "Install the iOS app from the App Store.")
                StepRowMac(number: 2, title: "Join the same Wi-Fi",
                           detail: "Both devices must be on the same network.")
                StepRowMac(number: 3, title: "Enter the pairing code",
                           detail: "Open Devices here to show the 4-digit code, then type it on the phone.")
            }
            .padding(.top, 22)
            .padding(.horizontal, 44)
            .frame(maxWidth: .infinity, alignment: .leading)
            Spacer(minLength: 0)
        }
    }

    // MARK: Footer

    private var footer: some View {
        HStack {
            if page > 0 {
                Button("Back") { withAnimation(.snappy) { page -= 1 } }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            HStack(spacing: 6) {
                ForEach(0 ..< pageCount, id: \.self) { i in
                    Capsule()
                        .fill(i == page ? Theme.Palette.brand : Color.secondary.opacity(0.25))
                        .frame(width: i == page ? 18 : 6, height: 6)
                        .animation(.snappy, value: page)
                }
            }
            Spacer()
            Button(isLast ? "Get Started" : "Continue") {
                if isLast { onFinish() } else { withAnimation(.snappy) { page += 1 } }
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.Palette.brand)
            .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }
}

// MARK: - Step scaffold

private struct FeatureStep<Hero: View>: View {
    @ViewBuilder let hero: () -> Hero
    let title: String
    let subtitle: String

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            hero().frame(height: 150)
            Text(title)
                .font(.system(size: 21, weight: .bold))
                .padding(.top, 24)
            Text(subtitle)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 6)
                .padding(.horizontal, 48)
            Spacer(minLength: 0)
        }
    }
}

// MARK: - Hero graphics

private struct WorkspacesHeroMac: View {
    private let tiles: [(String, Color)] = [
        ("safari.fill", Color(hex: "#2F6BFF")),
        ("terminal.fill", Color(hex: "#0E1116")),
        ("folder.fill", .orange),
        ("message.fill", Theme.Palette.brand),
    ]

    var body: some View {
        LazyVGrid(columns: [GridItem(.fixed(58), spacing: 12), GridItem(.fixed(58), spacing: 12)], spacing: 12) {
            ForEach(0 ..< 4, id: \.self) { i in
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Theme.Palette.windowBackground)
                    .frame(width: 58, height: 58)
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.Palette.hairline))
                    .overlay {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(tiles[i].1.opacity(0.16))
                            .frame(width: 32, height: 32)
                            .overlay(Image(systemName: tiles[i].0).font(.system(size: 15, weight: .semibold)).foregroundStyle(tiles[i].1))
                    }
                    .overlay(alignment: .bottomTrailing) {
                        if i == 0 {
                            Image(systemName: "play.fill")
                                .font(.system(size: 7, weight: .bold)).foregroundStyle(.white)
                                .frame(width: 17, height: 17)
                                .background(Theme.Palette.brand, in: Circle())
                                .overlay(Circle().strokeBorder(Theme.Palette.surface, lineWidth: 1.5))
                                .offset(x: 4, y: 4)
                        }
                    }
                    .shadow(color: .black.opacity(0.05), radius: 5, y: 2)
            }
        }
    }
}

private struct TerminalHeroMac: View {
    @State private var blink = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 5) {
                Circle().fill(Color(hex: "#FF5F57")).frame(width: 7, height: 7)
                Circle().fill(Color(hex: "#FEBC2E")).frame(width: 7, height: 7)
                Circle().fill(Color(hex: "#28C840")).frame(width: 7, height: 7)
            }
            .padding(.horizontal, 11).padding(.vertical, 8)
            Rectangle().fill(Color.white.opacity(0.08)).frame(height: 0.5)
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 5) {
                    Text("➜").foregroundStyle(Theme.Palette.brand)
                    Text("~").foregroundStyle(Color(hex: "#4EA1FF"))
                    Text("claude").foregroundStyle(.white)
                }
                HStack(spacing: 5) {
                    Text("➜").foregroundStyle(Theme.Palette.brand)
                    Text("~").foregroundStyle(Color(hex: "#4EA1FF"))
                    RoundedRectangle(cornerRadius: 1).fill(Theme.Palette.brand)
                        .frame(width: 7, height: 14).opacity(blink ? 0.15 : 1)
                }
            }
            .font(.system(size: 12, design: .monospaced))
            .padding(11)
        }
        .frame(width: 210)
        .background(Color(hex: "#0B0E12"), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.white.opacity(0.08)))
        .shadow(color: .black.opacity(0.2), radius: 14, y: 8)
        .onAppear { withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) { blink = true } }
    }
}

private struct BeamHeroMac: View {
    var body: some View {
        HStack(spacing: 0) {
            glyph("iphone")
            HStack(spacing: 5) {
                ForEach(0 ..< 3, id: \.self) { _ in
                    Circle().fill(Theme.Palette.brand).frame(width: 5, height: 5)
                }
            }
            .padding(.horizontal, 12)
            glyph("macbook")
        }
    }

    private func glyph(_ name: String) -> some View {
        Image(systemName: name)
            .font(.system(size: 40, weight: .regular))
            .foregroundStyle(name == "macbook" ? Theme.Palette.brand : .primary)
    }
}

private struct StepRowMac: View {
    let number: Int
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Theme.Palette.brand)
                .frame(width: 24, height: 24)
                .background(Theme.Palette.brand.opacity(0.14), in: Circle())
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 13, weight: .semibold))
                Text(detail).font(.system(size: 12)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
