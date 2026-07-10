import FipleKit
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

/// "Send to Mac": pick photos/videos or files — they land in the Mac's
/// Downloads (images also on its clipboard). Multi-select sends the whole
/// batch in one go, one transfer after another. Text/clipboard has no UI
/// here: Universal Clipboard and Share → Fiple already own that path.
struct SendToMacView: View {
    let controller: RemoteController

    @State private var pickedPhotos: [PhotosPickerItem] = []
    @State private var showFileImporter = false
    // Batch bookkeeping: which item is in flight and how the run went, so the
    // status strip can say "Sending 2 of 5" instead of per-file noise.
    @State private var batchTotal = 0
    @State private var batchIndex = 0
    @State private var batchFailed = 0
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                    fileCard
                }
                .padding(.horizontal, Theme.Spacing.lg)
                .padding(.top, Theme.Spacing.md)
            }
            .background(Theme.Palette.background)
            .navigationTitle("Send to Mac")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        .onChange(of: pickedPhotos) { _, items in
            guard !items.isEmpty else { return }
            Task { await sendPickedBatch(items) }
        }
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: [.item],
            allowsMultipleSelection: true
        ) { result in
            guard case let .success(urls) = result, !urls.isEmpty else { return }
            Task { await sendFileBatch(urls) }
        }
        .onDisappear { controller.resetBeamState() }
    }

    // MARK: File → Downloads

    private var fileCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            VStack(spacing: 0) {
                PhotosPicker(
                    selection: $pickedPhotos,
                    maxSelectionCount: 30,
                    matching: .any(of: [.images, .videos])
                ) {
                    PickerRow(icon: "photo.on.rectangle.angled", title: "Photos & Videos",
                              subtitle: "Pick several — they send in one go")
                }
                .buttonStyle(.plain)

                Divider().padding(.leading, 60)

                Button {
                    showFileImporter = true
                } label: {
                    PickerRow(icon: "folder", title: "Choose File",
                              subtitle: "From Files or iCloud Drive")
                }
                .buttonStyle(.plain)

                if hasBeamStatus {
                    Divider().padding(.leading, 60)
                    beamStatus
                        .padding(Theme.Spacing.lg)
                }
            }
            .background(Theme.Palette.surface, in: RoundedRectangle(cornerRadius: 16))

            Text("Files land in the Downloads folder on your Mac. Images are also copied to its clipboard — ready to ⌘V.")
                .font(.fiple(12))
                .foregroundStyle(Theme.Palette.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 4)
        }
    }


    private var hasBeamStatus: Bool {
        if case .idle = controller.beamState { return false }
        return true
    }

    @ViewBuilder private var beamStatus: some View {
        switch controller.beamState {
        case .idle:
            EmptyView()
        case let .sending(progress):
            VStack(alignment: .leading, spacing: 6) {
                Text(batchTotal > 1
                    ? "Sending \(batchIndex) of \(batchTotal)…"
                    : "Sending… \(Int(progress * 100))%")
                    .font(.fiple(13, .medium))
                    .foregroundStyle(Theme.Palette.secondary)
                // For a batch the bar covers the whole run, not just this file.
                ProgressView(value: batchTotal > 1
                    ? (Double(batchIndex - 1) + progress) / Double(batchTotal)
                    : progress)
                    .tint(Theme.Palette.brand)
            }
        case let .done(fileName):
            Label {
                Text(batchTotal > 1
                    ? "\(batchTotal - batchFailed) of \(batchTotal) saved to Downloads"
                    : "“\(fileName)” saved to Downloads")
                    .font(.fiple(14, .medium))
            } icon: {
                Image(systemName: batchFailed == 0 ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                    .foregroundStyle(batchFailed == 0 ? Theme.Palette.brand : .orange)
            }
        case let .failed(message):
            Label {
                Text(batchTotal > 1 && batchTotal > batchFailed
                    ? "\(batchTotal - batchFailed) of \(batchTotal) saved — the rest failed"
                    : message)
                    .font(.fiple(14))
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            }
        }
    }

    // MARK: Sending

    private func sendPickedBatch(_ items: [PhotosPickerItem]) async {
        batchTotal = items.count
        batchFailed = 0
        let stamp = Date().formatted(.iso8601.year().month().day().timeSeparator(.omitted).time(includingFractionalSeconds: false))
        // Pipeline: the next item exports from the photo library (or downloads
        // from iCloud) WHILE the current one streams to the Mac — otherwise
        // every photo pays load + send back to back.
        var pendingLoad = loadTask(for: items[0])
        for (index, item) in items.enumerated() {
            batchIndex = index + 1
            let data = await pendingLoad.value
            if index + 1 < items.count { pendingLoad = loadTask(for: items[index + 1]) }
            guard let data else {
                batchFailed += 1
                continue
            }
            // Best-available name: the photo library rarely exposes one, so
            // fall back to a timestamped name (indexed within the batch).
            let ext = item.supportedContentTypes.first?.preferredFilenameExtension ?? "jpg"
            let suffix = items.count > 1 ? "-\(index + 1)" : ""
            await controller.beamFile(name: "iPhone \(stamp)\(suffix).\(ext)", data: data)
            if case .failed = controller.beamState { batchFailed += 1 }
        }
        pickedPhotos = []
    }

    private func loadTask(for item: PhotosPickerItem) -> Task<Data?, Never> {
        Task { try? await item.loadTransferable(type: Data.self) }
    }

    private func sendFileBatch(_ urls: [URL]) async {
        batchTotal = urls.count
        batchFailed = 0
        for (index, url) in urls.enumerated() {
            batchIndex = index + 1
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            guard let data = try? Data(contentsOf: url) else {
                batchFailed += 1
                continue
            }
            await controller.beamFile(name: url.lastPathComponent, data: data)
            if case .failed = controller.beamState { batchFailed += 1 }
        }
    }
}

/// One picker row: brand-tinted icon square, title + subtitle, chevron.
private struct PickerRow: View {
    let icon: String
    let title: String
    let subtitle: String

    var body: some View {
        HStack(spacing: Theme.Spacing.md) {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Theme.Palette.brand.opacity(0.12))
                .frame(width: 36, height: 36)
                .overlay(
                    Image(systemName: icon)
                        .font(.fiple(16, .semibold))
                        .foregroundStyle(Theme.Palette.brand)
                )
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.fiple(16, .semibold)).foregroundStyle(Theme.Palette.label)
                Text(subtitle).font(.fiple(13)).foregroundStyle(Theme.Palette.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.fiple(13, .semibold))
                .foregroundStyle(Theme.Palette.secondary)
        }
        .padding(Theme.Spacing.lg)
        .contentShape(Rectangle())
    }
}
