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
        _colorHex = State(initialValue: tile?.colorHex ?? "#2DA44E")
        // A workspace is a preset of 2+ actions, so a brand-new one opens with two
        // empty action rows to fill in; editing keeps the tile's real actions.
        _drafts = State(initialValue: tile?.actions.map(ActionDraft.init) ?? [ActionDraft(), ActionDraft()])
    }

    /// Fully-filled action rows (empty rows don't count).
    private var validActionCount: Int { drafts.filter { $0.toAction() != nil }.count }

    /// A workspace is a preset that opens several things at once, so it needs a
    /// name and at least two actions — a single app belongs in the Fiple Bar.
    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && validActionCount >= 2
    }

    /// The workspace colour, used to tint the preview, accents and the Save button.
    private var base: Color { Color(hex: colorHex) }

    /// A live `Tile` assembled from the current form state so the preview card at
    /// the top of the editor updates as the user types, picks a colour, or adds
    /// actions — the editor shows exactly what the tile will look like.
    private var previewTile: Tile {
        Tile(
            name: name.trimmingCharacters(in: .whitespaces).isEmpty ? "Workspace name" : name,
            subtitle: subtitle.trimmingCharacters(in: .whitespaces).isEmpty ? nil : subtitle,
            iconSystemName: icon,
            iconImageData: iconImageData,
            colorHex: colorHex,
            actions: drafts.compactMap { $0.toAction() }
        )
    }

    /// The name field may be overwritten by an auto-fill when it's blank or still
    /// holds a value we filled in ourselves — but never a name the user typed.
    private var isNameAutoFillable: Bool {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty || trimmed == autoFilledName
    }

    /// While only one action is filled in, picking that app/URL derives the tile's
    /// identity (name + icon). Once a second action is added it's a real workspace
    /// and the name/icon are the user's to set — more apps must not hijack them.
    private var isIdentityAutoFillable: Bool { validActionCount <= 1 }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(spacing: Theme.Spacing.lg) {
                    LivePreviewCard(tile: previewTile)
                    appearancePanel
                    actionsPanel
                }
                .padding(Theme.Spacing.lg)
            }
            .background(Theme.Palette.windowBackground)
            Divider()
            footer
        }
        .frame(width: 480, height: 620)
        .background(Theme.Palette.windowBackground)
        .preferredColorScheme(.light) // keep the editor light like the rest of the app
        .task {
            // Only apps are enumerated (via Spotlight). Shortcuts can't be listed
            // from the App Sandbox without the Apple-events exception App Review
            // rejected, so the user types a shortcut's name instead (it still runs
            // via the `shortcuts://` URL scheme).
            installedApps = await InstalledApps.all()
        }
    }

    // MARK: - Chrome

    private var header: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(original == nil ? "New Workspace" : "Edit Workspace")
                .font(.system(size: 17, weight: .bold))
            Text("Set up what this tile launches, then tap it from your iPhone.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Theme.Spacing.xl)
        .padding(.vertical, Theme.Spacing.lg)
        .background(Theme.Palette.surface)
    }

    private var footer: some View {
        HStack {
            Button("Cancel") { dismiss() }
                .keyboardShortcut(.cancelAction)
            Spacer()
            Button {
                save()
            } label: {
                Text(original == nil ? "Create Workspace" : "Save Changes")
                    .fontWeight(.semibold)
                    .frame(minWidth: 120)
            }
            .buttonStyle(.borderedProminent)
            .tint(base)
            .keyboardShortcut(.defaultAction)
            .disabled(!isValid)
        }
        .padding(.horizontal, Theme.Spacing.xl)
        .padding(.vertical, Theme.Spacing.md)
        .background(Theme.Palette.surface)
    }

    // MARK: - Panels

    private var appearancePanel: some View {
        editorSection("Appearance", systemImage: "paintpalette.fill") {
            EditorField(label: "Name", text: $name, prompt: "Workspace name")
            EditorField(label: "Description", text: $subtitle, prompt: "Everything you need to code")
            iconBlock
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                Text("Colour")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                swatches
            }
        }
    }

    /// A curated set of workspace glyphs the user can pick from. When an app logo
    /// has been auto-filled it's shown first as the current choice; tapping any
    /// symbol switches the icon to that coloured glyph instead.
    private static let iconSymbols = [
        "square.grid.2x2", "briefcase.fill", "hammer.fill",
        "chevron.left.forwardslash.chevron.right", "terminal.fill", "paintbrush.pointed.fill",
        "book.fill", "graduationcap.fill", "bubble.left.and.bubble.right.fill",
        "globe", "envelope.fill", "music.note",
        "film.fill", "gamecontroller.fill", "cart.fill", "star.fill",
    ]

    private var iconBlock: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("Icon")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 40, maximum: 40), spacing: 10)],
                alignment: .leading,
                spacing: 10
            ) {
                if let iconImageData, let image = NSImage(data: iconImageData) {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFit()
                        .padding(6)
                        .frame(width: 40, height: 40)
                        .background(base.opacity(0.12), in: RoundedRectangle(cornerRadius: Theme.Radius.tile))
                        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.tile).strokeBorder(base, lineWidth: 2))
                        .help("Currently using the app logo")
                }
                ForEach(Self.iconSymbols, id: \.self) { symbol in
                    symbolChip(symbol)
                }
            }
            if iconImageData != nil {
                Text("Tap a symbol to use it instead of the app logo.")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private func symbolChip(_ symbol: String) -> some View {
        let selected = iconImageData == nil && icon == symbol
        return Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                icon = symbol
                iconImageData = nil
            }
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(selected ? .white : base)
                .frame(width: 40, height: 40)
                .background(selected ? base : base.opacity(0.12), in: RoundedRectangle(cornerRadius: Theme.Radius.tile))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(symbol)
    }

    private var actionsPanel: some View {
        editorSection("Actions", systemImage: "bolt.fill") {
            ForEach($drafts) { $draft in
                ActionDraftRow(
                    draft: $draft,
                    installedApps: installedApps,
                    accent: base,
                    onAppChosen: applyAppMetadata,
                    onURLChanged: applyURLMetadata
                ) {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        drafts.removeAll { $0.id == draft.id }
                    }
                }
                .padding(Theme.Spacing.md)
                .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: Theme.Radius.control))
                .overlay(RoundedRectangle(cornerRadius: Theme.Radius.control).strokeBorder(Theme.Palette.hairline))
            }
            Button {
                withAnimation(.easeInOut(duration: 0.15)) { drafts.append(ActionDraft()) }
            } label: {
                Label("Add action", systemImage: "plus")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(base)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(base.opacity(0.08), in: RoundedRectangle(cornerRadius: Theme.Radius.control))
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.Radius.control)
                            .strokeBorder(base.opacity(0.3), style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
                    )
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if validActionCount < 2 {
                Label(
                    "A workspace opens at least two things at once — add \(2 - validActionCount) more.",
                    systemImage: "info.circle"
                )
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    /// A titled white card panel matching the app's card language.
    private func editorSection(
        _ title: String,
        systemImage: String,
        @ViewBuilder content: () -> some View
    ) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Label(title, systemImage: systemImage)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
                .labelStyle(.titleAndIcon)
            content()
        }
        .padding(Theme.Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .fipleCard()
    }

    /// Human-readable swatch names for VoiceOver, keyed by hex.
    private static let swatchNames: [String: String] = [
        "#2DA44E": "Green",
        "#3B82F6": "Blue",
        "#8B5CF6": "Purple",
        "#EF4444": "Red",
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
                        .frame(width: 24, height: 24)
                        .overlay(Circle().strokeBorder(.white, lineWidth: selected ? 2 : 0))
                        .overlay(
                            Circle()
                                .strokeBorder(Color(hex: hex), lineWidth: selected ? 2 : 0)
                                .padding(-4)
                        )
                        .shadow(color: Color(hex: hex).opacity(selected ? 0.4 : 0), radius: 4, y: 1)
                        .frame(width: 44, height: 44) // ≥44pt hit target
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Self.swatchNames[hex] ?? "Color \(index + 1)")
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
    }

    /// Picking an app only suggests a name (unless the user typed their own). The
    /// workspace icon is *not* taken from the app — a preset of several apps
    /// shouldn't wear one app's logo, so the icon is the user's to pick above.
    private func applyAppMetadata(_ app: InstalledApp) {
        guard isIdentityAutoFillable, isNameAutoFillable else { return }
        name = app.name
        autoFilledName = app.name
    }

    /// Typing a URL only suggests a name from the domain — the site's favicon is
    /// never used as the workspace icon (the user picks the icon themselves).
    private func applyURLMetadata(_ raw: String) {
        guard let host = URLInput.webURL(from: raw)?.host(), host.contains(".") else { return }
        guard isIdentityAutoFillable, isNameAutoFillable else { return }
        let pretty = Self.prettyName(fromHost: host)
        name = pretty
        autoFilledName = pretty
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

/// A live, non-interactive preview of the workspace card the user is building —
/// the hero of the editor. It mirrors the real `WorkspaceCard` (icon, name,
/// stats, tinted wash) minus the menu and Edit button, and animates as the form
/// changes so "what am I making?" is always answered on screen.
private struct LivePreviewCard: View {
    let tile: Tile

    private var base: Color { Color(hex: tile.colorHex) }
    private var accent: Accent { Accent(hex: tile.colorHex) }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            HStack(alignment: .top, spacing: Theme.Spacing.md) {
                IconTile(
                    iconImageData: tile.iconImageData,
                    systemName: tile.iconSystemName,
                    colorHex: tile.colorHex,
                    size: 46
                )
                VStack(alignment: .leading, spacing: 2) {
                    Text(tile.name).font(Theme.Font.cardTitle).lineLimit(1)
                    if let subtitle = tile.subtitle, !subtitle.isEmpty {
                        Text(subtitle).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                    } else {
                        Text("Add a short description").font(.subheadline).foregroundStyle(.tertiary).lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
            }

            HStack(spacing: 0) {
                StatColumn(value: tile.appCount, label: "Apps")
                Rectangle()
                    .fill(Theme.Palette.hairline)
                    .frame(width: 1, height: 26)
                    .padding(.horizontal, Theme.Spacing.lg)
                StatColumn(value: tile.websiteCount, label: "Websites")
                Spacer()
                Label("Launches from iPhone", systemImage: "iphone.gen3")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(Theme.Spacing.xl)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            ZStack {
                Theme.Palette.surface
                accent.cardGradient
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .strokeBorder(base.opacity(0.14))
        )
        .shadow(color: base.opacity(0.18), radius: 16, y: 6)
        .animation(.easeInOut(duration: 0.22), value: tile.colorHex)
    }
}

/// A labelled text field styled to match the editor's card panels instead of the
/// stock grouped-form row.
private struct EditorField: View {
    let label: String
    @Binding var text: String
    let prompt: String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
            TextField("", text: $text, prompt: Text(prompt))
                .textFieldStyle(.plain)
                .font(.system(size: 14))
                .padding(.horizontal, 11)
                .padding(.vertical, 8)
                .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: Theme.Radius.control))
                .overlay(RoundedRectangle(cornerRadius: Theme.Radius.control).strokeBorder(Theme.Palette.hairline))
        }
    }
}

private struct ActionDraftRow: View {
    @Binding var draft: ActionDraft
    let installedApps: [InstalledApp]
    /// The workspace's accent colour, so the App/URL toggle matches the editor's
    /// theme instead of the stock blue segmented control.
    var accent: Color = Theme.Palette.brand
    let onAppChosen: (InstalledApp) -> Void
    let onURLChanged: (String) -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                kindToggle
                Spacer()
                Button(role: .destructive, action: onDelete) {
                    Image(systemName: "trash")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Remove this action")
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

    /// A compact App / URL toggle tinted with the workspace accent — replaces the
    /// stock `.segmented` picker, whose selected segment was always system blue.
    private var kindToggle: some View {
        HStack(spacing: 0) {
            ForEach(ActionDraft.Kind.allCases) { kind in
                let selected = draft.kind == kind
                Button {
                    withAnimation(.easeOut(duration: 0.12)) { draft.kind = kind }
                } label: {
                    Text(kind.rawValue)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(selected ? .white : .secondary)
                        .frame(width: 58, height: 26)
                        .background(selected ? accent : .clear, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(Color.black.opacity(0.05), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
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
