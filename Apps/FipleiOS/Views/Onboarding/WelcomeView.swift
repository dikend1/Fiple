import SwiftUI

/// First-launch onboarding: a paged, illustrated walkthrough — each feature
/// gets a composed "hero" graphic (not a text row), with a light entrance
/// animation as you swipe. Ends on the three-step connect guide.
struct WelcomeView: View {
    let onFinish: () -> Void

    @State private var page = 0
    /// Pages: 0 welcome · 1 workspaces · 2 terminal · 3 tools · 4 connect.
    private let pageCount = 5
    private var isLast: Bool { page == pageCount - 1 }

    init(onFinish: @escaping () -> Void) {
        self.onFinish = onFinish
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-welcome-connect") {
            _page = State(initialValue: 4)
        }
        // "-welcome-page N": start on page N, for screenshots.
        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "-welcome-page"), i + 1 < args.count, let n = Int(args[i + 1]) {
            _page = State(initialValue: n)
        }
        #endif
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            background.ignoresSafeArea()

            VStack(spacing: 0) {
                TabView(selection: $page) {
                    welcomePage.tag(0)
                    FeaturePage(
                        hero: { WorkspacesHero(active: page == 1) },
                        title: "Workspaces",
                        subtitle: "Tap one tile to open a whole set of apps, sites and files on your Mac — your working context, restored in a second."
                    ).tag(1)
                    FeaturePage(
                        hero: { TerminalHero(active: page == 2) },
                        title: "Terminal",
                        subtitle: "A real shell on your Mac, right from your phone — behind your master password and Face ID."
                    ).tag(2)
                    FeaturePage(
                        hero: { ToolsHero(active: page == 3) },
                        title: "Send & clean up",
                        subtitle: "Beam photos and files straight to your Mac's Downloads, and clear out stale files to free up space."
                    ).tag(3)
                    connectPage.tag(4)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .animation(.snappy, value: page)

                footer
            }

            if !isLast {
                Button("Skip") { onFinish() }
                    .font(.fiple(15, .medium))
                    .foregroundStyle(Theme.Palette.secondary)
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
            }
        }
    }

    /// A soft brand glow at the top over the app background — alive, but not the
    /// flat-white or cream default.
    private var background: some View {
        LinearGradient(
            colors: [Theme.Palette.brand.opacity(0.10), Theme.Palette.background],
            startPoint: .top, endPoint: .center
        )
        .background(Theme.Palette.background)
    }

    // MARK: - Page 0: welcome

    private var welcomePage: some View {
        VStack(spacing: 0) {
            Spacer()
            FloatingLogo()
            Text("Welcome to Fiple")
                .font(.fiple(32, .bold))
                .foregroundStyle(Theme.Palette.label)
                .padding(.top, 28)
            Text("Your Mac, one tap from your iPhone.")
                .font(.fiple(17))
                .foregroundStyle(Theme.Palette.secondary)
                .multilineTextAlignment(.center)
                .padding(.top, 6)
            Spacer()
            Label {
                Text("Works over your own Wi-Fi. No cloud, no accounts — your devices talk directly.")
                    .font(.fiple(12))
                    .foregroundStyle(Theme.Palette.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: "lock.shield.fill")
                    .font(.fiple(14))
                    .foregroundStyle(Theme.Palette.brand)
            }
            .padding(.horizontal, 36)
            .padding(.bottom, 24)
        }
        .padding(.horizontal, 28)
    }

    // MARK: - Page 4: connect

    private var connectPage: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 24)
            ConnectHero(active: page == 4)
            Text("Connect Your Mac")
                .font(.fiple(30, .bold))
                .foregroundStyle(Theme.Palette.label)
                .padding(.top, 24)
            Text("Three steps, about a minute.")
                .font(.fiple(16))
                .foregroundStyle(Theme.Palette.secondary)
                .padding(.top, 4)

            VStack(alignment: .leading, spacing: 22) {
                StepRow(number: 1, title: "Open Fiple on your Mac",
                        detail: "Install the Mac app and launch it — it lives in the menu bar.")
                StepRow(number: 2, title: "Join the same Wi-Fi",
                        detail: "Your iPhone and Mac must be on the same network.")
                StepRow(number: 3, title: "Enter the pairing code",
                        detail: "Type the 4-digit code from the Mac's Devices page.")
            }
            .padding(.top, 32)
            .frame(maxWidth: .infinity, alignment: .leading)
            Spacer(minLength: 12)
        }
        .padding(.horizontal, 32)
    }

    // MARK: - Footer: dots + button

    private var footer: some View {
        VStack(spacing: 20) {
            HStack(spacing: 7) {
                ForEach(0 ..< pageCount, id: \.self) { i in
                    Capsule()
                        .fill(i == page ? Theme.Palette.brand : Theme.Palette.secondary.opacity(0.25))
                        .frame(width: i == page ? 22 : 7, height: 7)
                        .animation(.snappy, value: page)
                }
            }

            Button {
                if isLast { onFinish() }
                else { withAnimation(.snappy) { page += 1 } }
            } label: {
                Text(isLast ? "Get Started" : "Continue")
                    .font(.fiple(17, .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(Theme.Palette.brand, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
        }
        .padding(.horizontal, 28)
        .padding(.bottom, 14)
    }
}

// MARK: - Page scaffold

/// A feature page: a large hero graphic that animates in, then title + subtitle.
private struct FeaturePage<Hero: View>: View {
    @ViewBuilder let hero: () -> Hero
    let title: String
    let subtitle: String

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            hero()
                .frame(height: 240)
            Text(title)
                .font(.fiple(30, .bold))
                .foregroundStyle(Theme.Palette.label)
                .padding(.top, 36)
            Text(subtitle)
                .font(.fiple(16))
                .foregroundStyle(Theme.Palette.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 10)
                .padding(.horizontal, 8)
            Spacer()
            Spacer()
        }
        .padding(.horizontal, 32)
    }
}

// MARK: - Hero graphics

/// The app logo with a gentle, endless vertical float and a soft brand halo.
private struct FloatingLogo: View {
    @State private var up = false

    var body: some View {
        Image("FipleLogo")
            .resizable()
            .scaledToFit()
            .frame(width: 96, height: 96)
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .shadow(color: Theme.Palette.brand.opacity(0.28), radius: 24, y: 12)
            .offset(y: up ? -8 : 8)
            .onAppear {
                withAnimation(.easeInOut(duration: 2.2).repeatForever(autoreverses: true)) { up = true }
            }
    }
}

/// Applies a scale+fade+lift entrance whenever the page becomes active.
private struct HeroEntrance: ViewModifier {
    let active: Bool
    @State private var shown = false

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .scaleEffect(shown ? 1 : 0.92)
            .offset(y: shown ? 0 : 16)
            .onChange(of: active) { _, now in
                withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) { shown = now }
            }
            .onAppear { if active { withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) { shown = true } } }
    }
}

private extension View {
    func heroEntrance(_ active: Bool) -> some View { modifier(HeroEntrance(active: active)) }
}

/// A 2×2 grid of mini workspace tiles, the top-left one wearing a play badge —
/// a miniature of the real Home carousel.
private struct WorkspacesHero: View {
    let active: Bool
    private let tiles: [(String, Color)] = [
        ("safari.fill", Theme.Palette.brandLink),
        ("terminal.fill", Color(hex: "#0E1116")),
        ("folder.fill", .orange),
        ("message.fill", Theme.Palette.brand),
    ]

    var body: some View {
        LazyVGrid(columns: [GridItem(.fixed(84), spacing: 14), GridItem(.fixed(84), spacing: 14)], spacing: 14) {
            ForEach(0 ..< 4, id: \.self) { i in
                miniTile(tiles[i].0, tiles[i].1, showPlay: i == 0)
            }
        }
        .heroEntrance(active)
    }

    private func miniTile(_ icon: String, _ tint: Color, showPlay: Bool) -> some View {
        RoundedRectangle(cornerRadius: 20, style: .continuous)
            .fill(Theme.Palette.surface)
            .frame(width: 84, height: 84)
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Theme.Palette.hairline)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .fill(tint.opacity(0.16))
                    .frame(width: 44, height: 44)
                    .overlay(Image(systemName: icon).font(.system(size: 20, weight: .semibold)).foregroundStyle(tint))
            }
            .overlay(alignment: .bottomTrailing) {
                if showPlay {
                    Image(systemName: "play.fill")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 24, height: 24)
                        .background(Theme.Palette.brand, in: Circle())
                        .overlay(Circle().strokeBorder(Theme.Palette.surface, lineWidth: 2))
                        .offset(x: 6, y: 6)
                }
            }
            .shadow(color: .black.opacity(0.05), radius: 8, y: 4)
    }
}

/// A miniature terminal window with a green prompt and a blinking cursor.
private struct TerminalHero: View {
    let active: Bool
    @State private var blink = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Circle().fill(Color(hex: "#FF5F57")).frame(width: 9, height: 9)
                Circle().fill(Color(hex: "#FEBC2E")).frame(width: 9, height: 9)
                Circle().fill(Color(hex: "#28C840")).frame(width: 9, height: 9)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)

            Rectangle().fill(Color.white.opacity(0.08)).frame(height: 0.5)

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Text("➜").foregroundStyle(Theme.Palette.brand)
                    Text("~").foregroundStyle(Color(hex: "#4EA1FF"))
                    Text("claude").foregroundStyle(.white)
                }
                HStack(spacing: 0) {
                    Text("building your app…").foregroundStyle(.white.opacity(0.55))
                }
                HStack(spacing: 6) {
                    Text("➜").foregroundStyle(Theme.Palette.brand)
                    Text("~").foregroundStyle(Color(hex: "#4EA1FF"))
                    RoundedRectangle(cornerRadius: 1)
                        .fill(Theme.Palette.brand)
                        .frame(width: 9, height: 17)
                        .opacity(blink ? 0.15 : 1)
                }
            }
            .font(.system(size: 14, design: .monospaced))
            .padding(14)
        }
        .frame(width: 250)
        .background(Color(hex: "#0B0E12"), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(.white.opacity(0.08)))
        .shadow(color: .black.opacity(0.25), radius: 20, y: 12)
        .heroEntrance(active)
        .onAppear {
            withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) { blink = true }
        }
    }
}

/// Two mini tool cards — Send to Mac (beam) and Smart Trash (reclaim) — side by
/// side, echoing the real Tools tab.
private struct ToolsHero: View {
    let active: Bool

    var body: some View {
        HStack(spacing: 16) {
            card(icon: "square.and.arrow.up.fill", tint: Theme.Palette.brand,
                 title: "Send to Mac", detail: "Photo → Downloads")
            card(icon: "trash.fill", tint: .orange,
                 title: "Smart Trash", detail: "Free up 1.8 GB")
        }
        .heroEntrance(active)
    }

    private func card(icon: String, tint: Color, title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(tint.opacity(0.16))
                .frame(width: 48, height: 48)
                .overlay(Image(systemName: icon).font(.system(size: 22, weight: .semibold)).foregroundStyle(tint))
            Spacer(minLength: 14)
            Text(title).font(.fiple(15, .semibold)).foregroundStyle(Theme.Palette.label)
            Text(detail).font(.fiple(13, .medium)).foregroundStyle(tint).padding(.top, 2)
        }
        .padding(16)
        .frame(width: 150, height: 150, alignment: .topLeading)
        .background(Theme.Palette.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Theme.Palette.hairline))
        .shadow(color: .black.opacity(0.05), radius: 10, y: 4)
    }
}

/// Phone and Mac linked by a beam — the connect metaphor.
private struct ConnectHero: View {
    let active: Bool

    var body: some View {
        Image(systemName: "macbook.and.iphone")
            .font(.system(size: 72, weight: .regular))
            .foregroundStyle(Theme.Palette.brand)
            .heroEntrance(active)
    }
}

// MARK: - Connect step row

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
                Text(title).font(.fiple(16, .semibold)).foregroundStyle(Theme.Palette.label)
                Text(detail).font(.fiple(14)).foregroundStyle(Theme.Palette.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
