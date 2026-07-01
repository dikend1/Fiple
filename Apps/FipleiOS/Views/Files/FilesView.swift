import FipleKit
import QuickLook
import SwiftUI
import UniformTypeIdentifiers

/// Files: browse and download recent files from the Mac, from anywhere, via the
/// private iCloud cache. Works even when the Mac is asleep. Read-only — no edit,
/// delete, or upload-back.
struct FilesView: View {
    @State private var store = RemoteFilesStore()
    @State private var query = ""
    @State private var previewURL: URL?
    @State private var favoritesFull = false

    var body: some View {
        NavigationStack {
            Group {
                switch store.state {
                case .idle, .loading where store.files.isEmpty:
                    loadingOrEmpty
                case .unavailable(let message):
                    EmptyHint(icon: "icloud.slash", text: message)
                case .failed(let message):
                    EmptyHint(icon: "exclamationmark.icloud", text: message)
                default:
                    content
                }
            }
            .background(Theme.Palette.background)
            .navigationTitle("Files")
            .searchable(text: $query, prompt: "Search files")
            .refreshable { await store.refresh() }
            .task { await store.refresh() }
            .quickLookPreview($previewURL)
            .alert("Favorites limit reached", isPresented: $favoritesFull) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Unpin a file to add a new favorite.")
            }
        }
    }

    @ViewBuilder private var loadingOrEmpty: some View {
        if case .loading = store.state {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if store.files.isEmpty {
            EmptyHint(
                icon: "folder",
                text: "No recent files yet. Turn on Remote File Access in Fiple on your Mac."
            )
        }
    }

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                if let last = store.lastModified {
                    Text("Updated \(last.formatted(.relative(presentation: .named)))")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.Palette.secondary)
                        .padding(.horizontal, Theme.Spacing.lg)
                }

                section("Favorites", files: filter(store.pinned))
                section("Desktop", files: filter(store.files(in: .desktop)))
                section("Documents", files: filter(store.files(in: .documents)))
                section("Downloads", files: filter(store.files(in: .downloads)))
            }
            .padding(.vertical, Theme.Spacing.lg)
            .padding(.bottom, Theme.Spacing.xxl)
        }
    }

    private func filter(_ files: [RemoteFile]) -> [RemoteFile] {
        guard !query.isEmpty else { return files }
        return files.filter { $0.fileName.localizedCaseInsensitiveContains(query) }
    }

    @ViewBuilder
    private func section(_ title: String, files: [RemoteFile]) -> some View {
        if !files.isEmpty {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                Text(title.uppercased())
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.Palette.secondary)
                    .padding(.horizontal, Theme.Spacing.lg)

                LazyVStack(spacing: 0) {
                    ForEach(Array(files.enumerated()), id: \.element.id) { index, file in
                        Button { open(file) } label: {
                            FileRow(file: file, downloading: store.downloading.contains(file.recordName))
                        }
                        .buttonStyle(.plain)
                        .contextMenu { menu(for: file) }
                        if index < files.count - 1 {
                            Divider().padding(.leading, 68)
                        }
                    }
                }
                .fipleCard()
                .padding(.horizontal, Theme.Spacing.lg)
            }
        }
    }

    @ViewBuilder
    private func menu(for file: RemoteFile) -> some View {
        Button {
            Task {
                let ok = await store.setPinned(file, !file.isPinned)
                if !ok { favoritesFull = true }
            }
        } label: {
            Label(file.isPinned ? "Unpin" : "Pin to Favorites",
                  systemImage: file.isPinned ? "star.slash" : "star")
        }
        Button { open(file) } label: { Label("Download & Open", systemImage: "arrow.down.circle") }
    }

    private func open(_ file: RemoteFile) {
        Task {
            if let url = await store.download(file) { previewURL = url }
        }
    }
}

/// One file row: type glyph, name, size · date, favorite star / spinner.
private struct FileRow: View {
    let file: RemoteFile
    let downloading: Bool

    var body: some View {
        HStack(spacing: Theme.Spacing.md) {
            Image(systemName: Self.symbol(for: file.contentType))
                .font(.system(size: 20))
                .foregroundStyle(Theme.Palette.brand)
                .frame(width: 44, height: 44)
                .background(Theme.Palette.brand.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))

            VStack(alignment: .leading, spacing: 2) {
                Text(file.fileName)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.Palette.label)
                    .lineLimit(1)
                Text("\(Self.size(file.sizeBytes)) · \(file.modifiedAt.formatted(date: .abbreviated, time: .omitted))")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.Palette.secondary)
            }

            Spacer()

            if downloading {
                ProgressView()
            } else if file.isPinned {
                Image(systemName: "star.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.Palette.brand)
            }
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.Palette.secondary.opacity(0.6))
        }
        .padding(Theme.Spacing.md)
        .contentShape(Rectangle())
    }

    private static func size(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    /// SF Symbol chosen from the file's UTI — a friendly glyph without needing a
    /// real thumbnail.
    static func symbol(for contentType: String) -> String {
        guard let type = UTType(contentType) else { return "doc" }
        if type.conforms(to: .image) { return "photo" }
        if type.conforms(to: .movie) || type.conforms(to: .audiovisualContent) { return "film" }
        if type.conforms(to: .audio) { return "music.note" }
        if type.conforms(to: .pdf) { return "doc.richtext" }
        if type.conforms(to: .presentation) { return "rectangle.on.rectangle" }
        if type.conforms(to: .spreadsheet) { return "tablecells" }
        if type.conforms(to: .archive) { return "doc.zipper" }
        if type.conforms(to: .sourceCode) || type.conforms(to: .plainText) { return "doc.text" }
        return "doc"
    }
}
