import FipleKit
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

/// "Send to Mac": pick a photo/video or any file — it lands in the Mac's
/// Downloads (images also on its clipboard). Text/clipboard has no UI here:
/// Universal Clipboard and Share → Fiple already own that path.
struct SendToMacView: View {
    let controller: RemoteController

    @State private var pickedPhoto: PhotosPickerItem?
    @State private var showFileImporter = false
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
        .onChange(of: pickedPhoto) { _, item in
            guard let item else { return }
            Task { await sendPicked(item) }
        }
        .fileImporter(isPresented: $showFileImporter, allowedContentTypes: [.item]) { result in
            guard case let .success(url) = result else { return }
            Task { await sendFile(at: url) }
        }
        .onDisappear { controller.resetBeamState() }
    }

    // MARK: File → Downloads

    private var fileCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            SectionHeader("File to Downloads")

            VStack(spacing: 0) {
                PhotosPicker(selection: $pickedPhoto, matching: .any(of: [.images, .videos])) {
                    PickerRow(icon: "photo.on.rectangle.angled", title: "Photo or Video",
                              subtitle: "From your library")
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
                Text("Sending… \(Int(progress * 100))%")
                    .font(.fiple(13, .medium))
                    .foregroundStyle(Theme.Palette.secondary)
                ProgressView(value: progress).tint(Theme.Palette.brand)
            }
        case let .done(fileName):
            Label {
                Text("“\(fileName)” saved to Downloads").font(.fiple(14, .medium))
            } icon: {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.Palette.brand)
            }
        case let .failed(message):
            Label {
                Text(message).font(.fiple(14))
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            }
        }
    }

    // MARK: Sending

    private func sendPicked(_ item: PhotosPickerItem) async {
        guard let data = try? await item.loadTransferable(type: Data.self) else { return }
        // Best-available name: the photo library rarely exposes one, so fall
        // back to a timestamped name with the right extension.
        let ext = item.supportedContentTypes.first?.preferredFilenameExtension ?? "jpg"
        let stamp = Date().formatted(.iso8601.year().month().day().timeSeparator(.omitted).time(includingFractionalSeconds: false))
        await controller.beamFile(name: "iPhone \(stamp).\(ext)", data: data)
        pickedPhoto = nil
    }

    private func sendFile(at url: URL) async {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url) else { return }
        await controller.beamFile(name: url.lastPathComponent, data: data)
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
