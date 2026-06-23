import AppKit
import FipleKit
import SwiftUI

/// The "Fiple Bar": an editable grid of quick actions (apps, websites, files),
/// 8 per page (4×2). Hovering a filled tile reveals Remove; hovering an empty
/// slot reveals Add, which opens an App / URL / File chooser like New Workspace.
struct PinnedAppsSection: View {
    let store: TileStore
    let bar: PinnedAppsStore
    var onViewAll: () -> Void

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
                    BarTile(action: action) { bar.remove(action.id) }
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

/// A filled Fiple Bar tile: the action's real icon over its name. Hovering
/// reveals a Remove overlay; clicking removes the entry.
private struct BarTile: View {
    let action: Action
    let onRemove: () -> Void
    @State private var hovering = false

    private let radius: CGFloat = 16
    private let tileSize: CGFloat = 64

    var body: some View {
        Button(action: onRemove) {
            VStack(spacing: 7) {
                ZStack {
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .fill(Color.primary.opacity(0.04))
                        .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(Theme.Palette.hairline))

                    icon

                    if hovering {
                        EditOverlay(symbol: "minus", label: "Remove", radius: radius)
                    }
                }
                .frame(width: tileSize, height: tileSize)

                Text(title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help("Remove \(title) from Fiple Bar")
    }

    @ViewBuilder private var icon: some View {
        if let image = nsIcon {
            Image(nsImage: image)
                .resizable()
                .scaledToFit()
                .padding(10)
                .shadow(color: .black.opacity(0.12), radius: 3, y: 1)
        } else if case let .openURL(url) = action.kind, let host = url.host() {
            AsyncImage(url: URL(string: "https://www.google.com/s2/favicons?domain=\(host)&sz=128")) { phase in
                if case let .success(image) = phase {
                    image.resizable().scaledToFit().padding(14)
                } else {
                    Image(systemName: "globe").font(.system(size: 24, weight: .semibold)).foregroundStyle(.secondary)
                }
            }
        } else {
            Image(systemName: fallbackSymbol)
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(.secondary)
        }
    }

    private var nsIcon: NSImage? {
        switch action.kind {
        case let .launchApp(bundleID):
            guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
            return NSWorkspace.shared.icon(forFile: url.path)
        case let .openFile(path, _):
            return FileManager.default.fileExists(atPath: path) ? NSWorkspace.shared.icon(forFile: path) : nil
        case .openURL:
            return nil
        }
    }

    private var title: String {
        switch action.kind {
        case let .launchApp(bundleID):
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
                return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
            }
            return bundleID.split(separator: ".").last.map(String.init) ?? bundleID
        case let .openURL(url):
            return (url.host()?.replacingOccurrences(of: "www.", with: "")) ?? url.absoluteString
        case let .openFile(path, _):
            return (path as NSString).lastPathComponent
        }
    }

    private var fallbackSymbol: String {
        switch action.kind {
        case .launchApp: "app.dashed"
        case .openURL: "globe"
        case .openFile: "doc.fill"
        }
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
        .help("Add an app, website or file to Fiple Bar")
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

// MARK: - Add sheet (App / URL / File, like New Workspace)

private struct AddActionSheet: View {
    let onAdd: (ActionKind) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var draft = ActionDraft()
    @State private var apps: [InstalledApp] = []

    var body: some View {
        VStack(spacing: 0) {
            Text("Add to Fiple Bar").font(.headline).padding()
            Divider()
            Form {
                Picker("Type", selection: $draft.kind) {
                    ForEach(ActionDraft.Kind.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                switch draft.kind {
                case .launchApp:
                    BarAppField(apps: apps, bundleID: $draft.bundleID)
                case .openURL:
                    TextField("https://…", text: $draft.url)
                        .textFieldStyle(.roundedBorder)
                case .openFile:
                    HStack {
                        TextField("/path/to/file-or-folder", text: $draft.path)
                            .textFieldStyle(.roundedBorder)
                        Button("Choose…") { choose() }
                    }
                }
            }
            .formStyle(.grouped)
            Divider()
            HStack {
                Button("Cancel") { dismiss() }
                Spacer()
                Button("Add") {
                    if let action = draft.toAction() { onAdd(action.kind) }
                }
                .buttonStyle(.borderedProminent)
                .disabled(draft.toAction() == nil)
            }
            .padding()
        }
        .frame(width: 420, height: 340)
        .preferredColorScheme(.light)
        .task { apps = InstalledApps.all() }
    }

    private func choose() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        if panel.runModal() == .OK, let url = panel.url {
            draft.path = url.path
        }
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
