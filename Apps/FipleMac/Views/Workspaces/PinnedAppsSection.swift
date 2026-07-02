import AppKit
import FipleKit
import SwiftUI

/// The "Fiple Bar": an editable grid of quick actions (apps, websites,
/// shortcuts), 8 per page (4×2). Hovering a filled tile reveals Remove; hovering
/// an empty slot reveals Add, which opens an App / URL / Shortcut chooser.
struct PinnedAppsSection: View {
    let store: TileStore
    let bar: PinnedAppsStore
    var onViewAll: () -> Void
    /// Launches an action locally. Injected so the click goes through the same
    /// path as phone-triggered runs (and lands in Recent history).
    var onRun: (Action) -> Void

    @State private var scrolledPage: Int?
    @State private var isAdding = false

    private let columns = Array(repeating: GridItem(.flexible(), spacing: Theme.Spacing.lg), count: 4)
    private let perPage = 8

    private enum Slot: Identifiable {
        case action(Action)
        case empty(Int)
        var id: String {
            switch self {
            case let .action(action): "action:\(action.id)"
            case let .empty(index): "empty:\(index)"
            }
        }
    }

    var body: some View {
        let pages = chunk(slots, into: perPage)
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            header

            HStack(spacing: Theme.Spacing.md) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 0) {
                        ForEach(pages.indices, id: \.self) { page in
                            grid(pages[page])
                                .containerRelativeFrame(.horizontal)
                                .id(page)
                        }
                    }
                    .scrollTargetLayout()
                }
                .scrollPosition(id: $scrolledPage)
                .scrollTargetBehavior(.paging)

                if pages.count > 1 {
                    CarouselArrow { advance(pageCount: pages.count) }
                }
            }

            if pages.count > 1 {
                CarouselDots(count: pages.count, current: scrolledPage ?? 0)
            }
        }
        .task { bar.seedIfNeeded(from: store.tiles) }
        .sheet(isPresented: $isAdding) {
            AddActionSheet { kind in
                bar.add(kind)
                isAdding = false
            }
        }
    }

    private var header: some View {
        HStack {
            Text("Fiple Bar").font(.system(size: 18, weight: .bold))
            Spacer()
            Button("View all", action: onViewAll)
                .buttonStyle(.plain)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        }
    }

    private func grid(_ slots: [Slot]) -> some View {
        LazyVGrid(columns: columns, spacing: Theme.Spacing.xl) {
            ForEach(slots) { slot in
                switch slot {
                case let .action(action):
                    BarTile(action: action, onRun: { onRun(action) }, onRemove: { bar.remove(action.id) })
                case .empty:
                    EmptyBarSlot { isAdding = true }
                }
            }
        }
    }

    /// Actions padded with empty Add-slots so every page is a full grid of 8 and
    /// there's always at least one empty slot to add into.
    private var slots: [Slot] {
        var result = bar.actions.map { Slot.action($0) }
        let pageCount = max(1, Int(ceil(Double(result.count + 1) / Double(perPage))))
        let total = pageCount * perPage
        for i in result.count..<total { result.append(.empty(i)) }
        return result
    }

    private func advance(pageCount: Int) {
        let current = scrolledPage ?? 0
        withAnimation { scrolledPage = current + 1 < pageCount ? current + 1 : 0 }
    }
}

// MARK: - Tiles

/// A filled Fiple Bar tile: the action's real icon over its name. Clicking
/// launches the action locally (mirroring what a tap does on the phone);
/// removal lives behind a small hover ✕ and the context menu — never the
/// primary click.
private struct BarTile: View {
    let action: Action
    let onRun: () -> Void
    let onRemove: () -> Void
    @State private var hovering = false

    private let radius: CGFloat = 16
    private let tileSize: CGFloat = 64

    var body: some View {
        VStack(spacing: 7) {
            Button(action: run) {
                ZStack {
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .fill(Color.primary.opacity(0.04))
                        .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(Theme.Palette.hairline))

                    icon
                }
                .frame(width: tileSize, height: tileSize)
                .contentShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Launch \(title)")
            .overlay(alignment: .topTrailing) {
                if hovering {
                    Button(action: onRemove) {
                        Image(systemName: "xmark")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 18, height: 18)
                            .background(Color.black.opacity(0.6), in: Circle())
                    }
                    .buttonStyle(.plain)
                    // Tucked inside the tile corner so the paging ScrollView
                    // doesn't clip it.
                    .padding(3)
                    .transition(.opacity)
                    .help("Remove \(title) from Fiple Bar")
                    .accessibilityLabel("Remove \(title) from Fiple Bar")
                }
            }

            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.primary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .onHover { hovering = $0 }
        .contextMenu {
            Button("Remove from Fiple Bar", role: .destructive, action: onRemove)
        }
        .help("Launch \(title)")
    }

    /// Runs the action on this Mac via the injected launcher, so it goes
    /// through `ServerController.run` and lands in Recent history like a
    /// phone-triggered launch.
    private func run() {
        onRun()
    }

    @ViewBuilder private var icon: some View {
        if let image = nsIcon {
            Image(nsImage: image)
                .resizable()
                .scaledToFit()
                .padding(10)
                .shadow(color: .black.opacity(0.12), radius: 3, y: 1)
        } else if case let .openURL(url) = action.kind, let host = url.host() {
            BarFavicon(host: host)
        } else {
            Image(systemName: fallbackSymbol)
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(.secondary)
        }
    }

    /// App and shortcut icons via the session cache, so a tile redraw (hover,
    /// scroll, neighbouring edits) is a dictionary hit rather than a fresh
    /// NSWorkspace lookup.
    private var nsIcon: NSImage? {
        switch action.kind {
        case let .launchApp(bundleID):
            return AppIconCache.shared.icon(bundleID: bundleID)
        case .openURL:
            return nil
        }
    }

    private var title: String {
        switch action.kind {
        case let .launchApp(bundleID):
            return AppIconCache.shared.name(bundleID: bundleID)
                ?? (bundleID.split(separator: ".").last.map(String.init) ?? bundleID)
        case let .openURL(url):
            return (url.host()?.replacingOccurrences(of: "www.", with: "")) ?? url.absoluteString
        }
    }

    private var fallbackSymbol: String {
        switch action.kind {
        case .launchApp: "app.dashed"
        case .openURL: "globe"
        }
    }
}

/// A Fiple Bar favicon: loads through the shared session `FaviconCache` (so a
/// host is fetched at most once, instead of a network request per body redraw)
/// and renders with the bar tile's own padding and globe fallback — pixel-for-
/// pixel the same as the former inline `AsyncImage`.
private struct BarFavicon: View {
    let host: String
    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image).resizable().scaledToFit().padding(14)
            } else {
                Image(systemName: "globe").font(.system(size: 24, weight: .semibold)).foregroundStyle(.secondary)
            }
        }
        .task(id: host) { image = await FaviconCache.shared.icon(for: host) }
    }
}

/// An empty Fiple Bar slot: a soft well that reveals an Add affordance on hover.
private struct EmptyBarSlot: View {
    let onAdd: () -> Void
    @State private var hovering = false

    private let radius: CGFloat = 16
    private let tileSize: CGFloat = 64

    var body: some View {
        Button(action: onAdd) {
            VStack(spacing: 7) {
                ZStack {
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .fill(Color.primary.opacity(hovering ? 0.07 : 0.035))
                        .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(Theme.Palette.hairline))

                    if hovering {
                        EditOverlay(symbol: "plus", label: "Add", radius: radius)
                    }
                }
                .frame(width: tileSize, height: tileSize)

                Text(" ").font(.system(size: 11, weight: .medium))
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help("Add an app or website to Fiple Bar")
    }
}

/// The hover affordance: a tinted scrim with a cream badge (+ / −) and caption.
private struct EditOverlay: View {
    let symbol: String
    let label: String
    let radius: CGFloat

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(Color.black.opacity(0.5))
            VStack(spacing: 4) {
                Image(systemName: symbol)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Color.black.opacity(0.7))
                    .frame(width: 26, height: 26)
                    .background(Color(hex: "#F1E9D8"), in: Circle())
                Text(label)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white)
            }
        }
        .transition(.opacity)
    }
}

// MARK: - Add sheet (App / URL / Shortcut, like New Workspace)

private struct AddActionSheet: View {
    let onAdd: (ActionKind) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var draft = ActionDraft()
    @State private var apps: [InstalledApp] = []

    private var brand: Color { Theme.Palette.brand }

    var body: some View {
        VStack(spacing: 0) {
            header

            HStack(spacing: 10) {
                TypeTile(title: "App", subtitle: "An installed Mac app",
                         systemImage: "square.grid.2x2.fill",
                         selected: draft.kind == .launchApp) { draft.kind = .launchApp }
                TypeTile(title: "Website", subtitle: "Any link",
                         systemImage: "globe",
                         selected: draft.kind == .openURL) { draft.kind = .openURL }
            }
            .padding(.horizontal, 20)

            input
                .padding(.horizontal, 20)
                .padding(.top, 16)

            Spacer(minLength: 0)
            Divider()
            footer
        }
        .frame(width: 460, height: 400)
        .background(Color.white)
        .preferredColorScheme(.light)
        .task { apps = await InstalledApps.all() }
    }

    private var header: some View {
        VStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(brand.opacity(0.14))
                    .frame(width: 54, height: 54)
                Image(systemName: "plus")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(brand)
            }
            Text("Add to Fiple Bar").font(.system(size: 18, weight: .bold))
            Text("Pin an app or a website here, then open it from your iPhone with one tap.")
                .font(.callout).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 28)
        }
        .padding(.top, 26).padding(.bottom, 20)
    }

    @ViewBuilder private var input: some View {
        switch draft.kind {
        case .launchApp:
            BarAppField(apps: apps, bundleID: $draft.bundleID)
        case .openURL:
            HStack(spacing: 8) {
                Image(systemName: "globe").foregroundStyle(.secondary)
                TextField("example.com", text: $draft.url).textFieldStyle(.plain)
            }
            .padding(.horizontal, 12).padding(.vertical, 10)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(.black.opacity(0.1)))
        }
    }

    private var footer: some View {
        HStack {
            Button("Cancel") { dismiss() }
                .buttonStyle(.plain).foregroundStyle(.secondary)
            Spacer()
            Button {
                if let action = draft.toAction() { onAdd(action.kind) }
            } label: {
                Text("Add to Bar").fontWeight(.semibold)
                    .padding(.horizontal, 18).padding(.vertical, 7)
            }
            .buttonStyle(.borderedProminent)
            .tint(brand)
            .disabled(draft.toAction() == nil)
        }
        .padding(18)
    }
}

/// A selectable App / Website tile for the add sheet.
private struct TypeTile: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .font(.system(size: 17, weight: .semibold))
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.system(size: 14, weight: .semibold))
                    Text(subtitle).font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .foregroundStyle(selected ? Theme.Palette.brand : .primary)
            .padding(.horizontal, 12).padding(.vertical, 11)
            .frame(maxWidth: .infinity)
            .background(
                selected ? Theme.Palette.brand.opacity(0.12) : Color.black.opacity(0.03),
                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(selected ? Theme.Palette.brand.opacity(0.5) : .black.opacity(0.07))
            )
        }
        .buttonStyle(.plain)
    }
}

/// A searchable app chooser (compact field + filterable popover).
private struct BarAppField: View {
    let apps: [InstalledApp]
    @Binding var bundleID: String
    @State private var showing = false
    @State private var query = ""

    private var selected: InstalledApp? { apps.first { $0.bundleID == bundleID } }
    private var filtered: [InstalledApp] {
        let q = query.trimmingCharacters(in: .whitespaces)
        return q.isEmpty ? apps : apps.filter { $0.name.localizedCaseInsensitiveContains(q) }
    }

    var body: some View {
        Button { showing = true } label: {
            HStack(spacing: 8) {
                if let app = selected {
                    Image(nsImage: app.icon).resizable().frame(width: 18, height: 18)
                    Text(app.name)
                } else {
                    Image(systemName: "app.dashed").foregroundStyle(.secondary)
                    Text("Choose an app…").foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.up.chevron.down").font(.caption2).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 7))
            .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(.black.opacity(0.12)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showing, arrowEdge: .bottom) {
            VStack(spacing: 0) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Search apps", text: $query).textFieldStyle(.plain)
                }
                .padding(8)
                Divider()
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(filtered) { app in
                            Button {
                                bundleID = app.bundleID
                                showing = false
                            } label: {
                                HStack(spacing: 8) {
                                    Image(nsImage: app.icon).resizable().frame(width: 18, height: 18)
                                    Text(app.name).lineLimit(1)
                                    Spacer()
                                    if app.bundleID == bundleID {
                                        Image(systemName: "checkmark").font(.caption).foregroundStyle(.tint)
                                    }
                                }
                                .padding(.horizontal, 10).padding(.vertical, 6)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .frame(height: 300)
            }
            .frame(width: 280)
        }
        .onChange(of: showing) { _, isShowing in
            if !isShowing { query = "" }
        }
    }
}

// MARK: - Helpers

/// Splits a list into fixed-size chunks (carousel pages).
private func chunk<T>(_ items: [T], into size: Int) -> [[T]] {
    guard size > 0 else { return [items] }
    return stride(from: 0, to: items.count, by: size).map {
        Array(items[$0..<Swift.min($0 + size, items.count)])
    }
}
