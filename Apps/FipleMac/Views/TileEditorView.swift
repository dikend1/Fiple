import AppKit
import FipleKit
import SwiftUI

/// Mutable form representation of an `Action` (text fields bind cleanly here,
/// then convert back to a typed `Action` on save).
struct ActionDraft: Identifiable {
    enum Kind: String, CaseIterable, Identifiable {
        case launchApp = "App"
        case openURL = "URL"
        var id: String { rawValue }
    }

    let id: UUID
    var kind: Kind
    var bundleID: String
    var url: String

    init() {
        id = UUID(); kind = .launchApp; bundleID = ""; url = ""
    }

    init(_ action: Action) {
        id = action.id
        bundleID = ""; url = ""
        switch action.kind {
        case let .launchApp(bundleID): kind = .launchApp; self.bundleID = bundleID
        case let .openURL(u): kind = .openURL; url = u.absoluteString
        // Shortcuts are no longer creatable in the UI; show any legacy shortcut
        // action as an empty App draft so the editor still opens cleanly.
        case .runShortcut: kind = .launchApp
        }
    }

    func toAction() -> Action? {
        switch kind {
        case .launchApp:
            guard !bundleID.isEmpty else { return nil }
            return Action(id: id, kind: .launchApp(bundleID: bundleID))
        case .openURL:
            guard let u = URLInput.webURL(from: url) else { return nil }
            return Action(id: id, kind: .openURL(u))
        }
    }
}

struct TileEditorView: View {
    let store: TileStore
    @Environment(\.dismiss) private var dismiss

    private let original: Tile?
    @State private var name: String
    @State private var subtitle: String
    @State private var icon: String
    @State private var iconImageData: Data?
    @State private var colorHex: String
    @State private var drafts: [ActionDraft]
    @State private var installedApps: [InstalledApp] = []
    /// The host we last fetched a favicon for, so typing doesn't refetch.
    @State private var faviconHost: String?
    /// The last name we auto-filled, so re-picking another app/URL can replace
    /// it — but a name the user typed by hand is left untouched.
    @State private var autoFilledName: String?

    init(store: TileStore, tile: Tile?) {
        self.store = store
        self.original = tile
        _name = State(initialValue: tile?.name ?? "")
        _subtitle = State(initialValue: tile?.subtitle ?? "")
        _icon = State(initialValue: tile?.iconSystemName ?? "square.grid.2x2")
        _iconImageData = State(initialValue: tile?.iconImageData)
        _colorHex = State(initialValue: tile?.colorHex ?? "#3B82F6")
        _drafts = State(initialValue: (tile?.actions ?? []).map(ActionDraft.init))
    }

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && drafts.contains { $0.toAction() != nil }
    }

    /// The name field may be overwritten by an auto-fill when it's blank or still
    /// holds a value we filled in ourselves — but never a name the user typed.
    private var isNameAutoFillable: Bool {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty || trimmed == autoFilledName
    }

    var body: some View {
        VStack(spacing: 0) {
            Text(original == nil ? "New Workspace" : "Edit Workspace").font(.headline).padding()
            Divider()
            Form {
                Section("Appearance") {
                    LabeledContent("Icon") {
                        HStack(spacing: 12) {
                            TileIconPreview(iconImageData: iconImageData, systemName: icon, colorHex: colorHex)
                            if iconImageData != nil {
                                Button("Use symbol") { iconImageData = nil }
                                    .controlSize(.small)
                            }
                        }
                    }
                    TextField("Name", text: $name)
                    TextField("Description", text: $subtitle, prompt: Text("Everything you need to code"))
                    swatches
                }
                Section("Actions") {
                    ForEach($drafts) { $draft in
                        ActionDraftRow(
                            draft: $draft,
                            installedApps: installedApps,
                            onAppChosen: applyAppMetadata,
                            onURLChanged: applyURLMetadata
                        ) {
                            drafts.removeAll { $0.id == draft.id }
                        }
                    }
                    Button { drafts.append(ActionDraft()) } label: {
                        Label("Add Action", systemImage: "plus.circle")
                    }
                }
            }
            .formStyle(.grouped)
            Divider()
            HStack {
                Button("Cancel") { dismiss() }
                Spacer()
                Button("Save") { save() }
                    .buttonStyle(.borderedProminent)
                    .disabled(!isValid)
            }
            .padding()
        }
        .frame(width: 460, height: 560)
        .preferredColorScheme(.light) // keep the editor light like the rest of the app
        .task {
            // Only apps are enumerated (via Spotlight). Shortcuts can't be listed
            // from the App Sandbox without the Apple-events exception App Review
            // rejected, so the user types a shortcut's name instead (it still runs
            // via the `shortcuts://` URL scheme).
            installedApps = await InstalledApps.all()
        }
    }

    /// Human-readable swatch names for VoiceOver, keyed by hex.
    private static let swatchNames: [String: String] = [
        "#3B82F6": "Blue",
        "#8B5CF6": "Purple",
        "#EF4444": "Red",
        "#10B981": "Green",
        "#F59E0B": "Orange",
        "#EC4899": "Pink",
        "#0EA5E9": "Sky Blue",
        "#64748B": "Gray",
    ]

    private var swatches: some View {
        // Zero HStack spacing: each swatch's ≥44pt hit target supplies the gaps
        // while the visible circle stays 22pt.
        HStack(spacing: 0) {
            ForEach(Array(TilePalette.swatches.enumerated()), id: \.element) { index, hex in
                let selected = colorHex == hex
                Button {
                    colorHex = hex
                } label: {
                    Circle()
                        .fill(Color(hex: hex))
                        .frame(width: 22, height: 22)
                        .overlay(Circle().strokeBorder(.primary, lineWidth: selected ? 2 : 0))
                        .frame(width: 44, height: 44) // ≥44pt hit target
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Self.swatchNames[hex] ?? "Color \(index + 1)")
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
    }

    /// Picking an app fills in a name (unless the user typed their own) and its
    /// real icon as the logo. Re-picking replaces a name we previously auto-filled.
    private func applyAppMetadata(_ app: InstalledApp) {
        if isNameAutoFillable { name = app.name; autoFilledName = app.name }
        iconImageData = app.iconPNG
        faviconHost = nil
    }

    /// Typing a URL fills in a name from the domain and fetches the site favicon.
    private func applyURLMetadata(_ raw: String) {
        guard let host = URLInput.webURL(from: raw)?.host(), host.contains(".") else { return }
        if isNameAutoFillable {
            let pretty = Self.prettyName(fromHost: host)
            name = pretty; autoFilledName = pretty
        }
        if icon == "square.grid.2x2" { icon = "globe" }
        guard host != faviconHost else { return }
        faviconHost = host
        Task { await loadFavicon(host: host) }
    }

    private func loadFavicon(host: String) async {
        guard let url = URL(string: "https://www.google.com/s2/favicons?domain=\(host)&sz=128") else { return }
        guard let (data, _) = try? await URLSession.shared.data(from: url),
              let image = NSImage(data: data), let png = AppIconRenderer.png(from: image) else { return }
        // Apply only if the user is still on this host (avoids a stale late result).
        if faviconHost == host { iconImageData = png }
    }

    /// "whooshly.app" → "Whooshly", "www.github.com" → "Github".
    private static func prettyName(fromHost host: String) -> String {
        let label = host.replacingOccurrences(of: "www.", with: "").split(separator: ".").first.map(String.init) ?? host
        return label.prefix(1).uppercased() + label.dropFirst()
    }

    private func save() {
        let actions = drafts.compactMap { $0.toAction() }
        let trimmedSubtitle = subtitle.trimmingCharacters(in: .whitespaces)
        let resolvedSubtitle = trimmedSubtitle.isEmpty ? nil : trimmedSubtitle
        if var tile = original {
            tile.name = name
            tile.subtitle = resolvedSubtitle
            tile.iconSystemName = icon
            tile.iconImageData = iconImageData
            tile.colorHex = colorHex
            tile.actions = actions
            store.update(tile)
        } else {
            store.add(Tile(
                name: name,
                subtitle: resolvedSubtitle,
                iconSystemName: icon,
                iconImageData: iconImageData,
                colorHex: colorHex,
                actions: actions
            ))
        }
        dismiss()
    }
}

/// Shows the tile's chosen logo, or its SF Symbol on the color swatch as a fallback.
struct TileIconPreview: View {
    let iconImageData: Data?
    let systemName: String
    let colorHex: String

    var body: some View {
        if let iconImageData, let image = NSImage(data: iconImageData) {
            Image(nsImage: image)
                .resizable()
                .frame(width: 32, height: 32)
                .clipShape(RoundedRectangle(cornerRadius: 7))
        } else {
            RoundedRectangle(cornerRadius: 7)
                .fill(Color(hex: colorHex))
                .frame(width: 32, height: 32)
                .overlay(Image(systemName: systemName).foregroundStyle(.white))
        }
    }
}

private struct ActionDraftRow: View {
    @Binding var draft: ActionDraft
    let installedApps: [InstalledApp]
    let onAppChosen: (InstalledApp) -> Void
    let onURLChanged: (String) -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Picker("Type", selection: $draft.kind) {
                    ForEach(ActionDraft.Kind.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                Button(role: .destructive, action: onDelete) {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
            }
            switch draft.kind {
            case .launchApp:
                AppPickerField(apps: installedApps, bundleID: $draft.bundleID, onChosen: onAppChosen)
            case .openURL:
                TextField("https://…", text: $draft.url)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: draft.url) { _, newValue in onURLChanged(newValue) }
            }
        }
        .padding(.vertical, 4)
    }
}

/// A searchable app chooser: a compact field showing the selected app, opening a
/// filterable popover list — far friendlier than a flat menu of every app.
private struct AppPickerField: View {
    let apps: [InstalledApp]
    @Binding var bundleID: String
    let onChosen: (InstalledApp) -> Void

    @State private var showing = false
    @State private var query = ""

    private var selected: InstalledApp? { apps.first { $0.bundleID == bundleID } }

    private var filtered: [InstalledApp] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return apps }
        return apps.filter { $0.name.localizedCaseInsensitiveContains(q) }
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
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2).foregroundStyle(.secondary)
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
                            appRow(app)
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

    private func appRow(_ app: InstalledApp) -> some View {
        Button {
            bundleID = app.bundleID
            onChosen(app)
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
