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
    @State private var colorHex: String
    @State private var drafts: [ActionDraft]
    @State private var installedApps: [InstalledApp] = []

    init(store: TileStore, tile: Tile?) {
        self.store = store
        self.original = tile
        _name = State(initialValue: tile?.name ?? "")
        _icon = State(initialValue: tile?.iconSystemName ?? "square.grid.2x2")
        _colorHex = State(initialValue: tile?.colorHex ?? "#3B82F6")
        _drafts = State(initialValue: (tile?.actions ?? []).map(ActionDraft.init))
    }

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && drafts.contains { $0.toAction() != nil }
    }

    var body: some View {
        VStack(spacing: 0) {
            Text(original == nil ? "New Tile" : "Edit Tile").font(.headline).padding()
            Divider()
            Form {
                Section("Appearance") {
                    TextField("Name", text: $name)
                    TextField("SF Symbol", text: $icon)
                    swatches
                }
                Section("Actions") {
                    ForEach($drafts) { $draft in
                        ActionDraftRow(draft: $draft, installedApps: installedApps) {
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
        .frame(width: 460, height: 520)
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

    private func save() {
        let actions = drafts.compactMap { $0.toAction() }
        if var tile = original {
            tile.name = name
            tile.iconSystemName = icon
            tile.colorHex = colorHex
            tile.actions = actions
            store.update(tile)
        } else {
            store.add(Tile(name: name, iconSystemName: icon, colorHex: colorHex, actions: actions))
        }
        dismiss()
    }
}

private struct ActionDraftRow: View {
    @Binding var draft: ActionDraft
    let installedApps: [InstalledApp]
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
                    ForEach(installedApps) { Text($0.name).tag($0.bundleID) }
                }
                .labelsHidden()
            case .openURL:
                TextField("https://…", text: $draft.url)
                    .textFieldStyle(.roundedBorder)
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
