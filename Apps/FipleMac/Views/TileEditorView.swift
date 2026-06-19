import AppKit
import FipleKit
import SwiftUI

/// Mutable form representation of an `Action` (text fields bind cleanly here,
/// then convert back to a typed `Action` on save).
struct ActionDraft: Identifiable {
    enum Kind: String, CaseIterable, Identifiable {
        case launchApp = "App"
        case openURL = "URL"
        case openFile = "File"
        var id: String { rawValue }
    }

    let id: UUID
    var kind: Kind
    var bundleID: String
    var url: String
    var path: String

    init() {
        id = UUID(); kind = .launchApp; bundleID = ""; url = ""; path = ""
    }

    init(_ action: Action) {
        id = action.id
        bundleID = ""; url = ""; path = ""
        switch action.kind {
        case let .launchApp(bundleID): kind = .launchApp; self.bundleID = bundleID
        case let .openURL(u): kind = .openURL; url = u.absoluteString
        case let .openFile(p, _): kind = .openFile; path = p
        }
    }

    func toAction() -> Action? {
        switch kind {
        case .launchApp:
            guard !bundleID.isEmpty else { return nil }
            return Action(id: id, kind: .launchApp(bundleID: bundleID))
        case .openURL:
            guard let u = URL(string: url), u.scheme != nil else { return nil }
            return Action(id: id, kind: .openURL(u))
        case .openFile:
            guard !path.isEmpty else { return nil }
            return Action(id: id, kind: .openFile(path: path, openWith: nil))
        }
    }
}

struct TileEditorView: View {
    let store: TileStore
    @Environment(\.dismiss) private var dismiss

    private let original: Tile?
    @State private var name: String
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
            Text(original == nil ? "New Tile" : "Edit Tile").font(.headline).padding()
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
        .task { installedApps = InstalledApps.all() }
    }

    private var swatches: some View {
        HStack {
            ForEach(TilePalette.swatches, id: \.self) { hex in
                Circle()
                    .fill(Color(hex: hex))
                    .frame(width: 22, height: 22)
                    .overlay(Circle().strokeBorder(.primary, lineWidth: colorHex == hex ? 2 : 0))
                    .onTapGesture { colorHex = hex }
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
        guard let host = URL(string: raw)?.host(), host.contains(".") else { return }
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
        if var tile = original {
            tile.name = name
            tile.iconSystemName = icon
            tile.iconImageData = iconImageData
            tile.colorHex = colorHex
            tile.actions = actions
            store.update(tile)
        } else {
            store.add(Tile(
                name: name,
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
                Picker("App", selection: $draft.bundleID) {
                    Text("Choose an app…").tag("")
                    ForEach(installedApps) { app in
                        HStack {
                            Image(nsImage: app.icon)
                                .resizable()
                                .frame(width: 16, height: 16)
                            Text(app.name)
                        }
                        .tag(app.bundleID)
                    }
                }
                .labelsHidden()
                .onChange(of: draft.bundleID) { _, newID in
                    if let app = installedApps.first(where: { $0.bundleID == newID }) { onAppChosen(app) }
                }
            case .openURL:
                TextField("https://…", text: $draft.url)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: draft.url) { _, newValue in onURLChanged(newValue) }
            case .openFile:
                HStack {
                    TextField("/path/to/file-or-folder", text: $draft.path)
                        .textFieldStyle(.roundedBorder)
                    Button("Choose…") { chooseFile() }
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func chooseFile() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        if panel.runModal() == .OK, let url = panel.url {
            draft.path = url.path
        }
    }
}
