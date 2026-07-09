import FipleKit
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

/// "Send to Mac": pick a photo/video or any file — it lands in the Mac's
/// Downloads — or type/paste text straight onto the Mac's clipboard.
struct SendToMacView: View {
    let controller: RemoteController

    @State private var pickedPhoto: PhotosPickerItem?
    @State private var showFileImporter = false
    @State private var clipboardText = ""
    @State private var clipboardSent = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    PhotosPicker(selection: $pickedPhoto, matching: .any(of: [.images, .videos])) {
                        Label("Photo or Video", systemImage: "photo.on.rectangle")
                    }
                    Button {
                        showFileImporter = true
                    } label: {
                        Label("Choose File", systemImage: "doc")
                    }
                } header: {
                    Text("Send a file to Downloads")
                } footer: {
                    beamStatus
                }

                Section {
                    TextField("Type or paste text…", text: $clipboardText, axis: .vertical)
                        .lineLimit(1 ... 5)
                    Button {
                        Task {
                            clipboardSent = await controller.sendClipboard(text: clipboardText)
                            if clipboardSent {
                                UINotificationFeedbackGenerator().notificationOccurred(.success)
                            }
                        }
                    } label: {
                        Label(clipboardSent ? "On your Mac's clipboard — press ⌘V" : "Put on Mac's Clipboard",
                              systemImage: clipboardSent ? "checkmark" : "doc.on.clipboard")
                    }
                    .disabled(clipboardText.isEmpty)
                } header: {
                    Text("Send text to the clipboard")
                }
            }
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
        .onChange(of: clipboardText) { _, _ in clipboardSent = false }
        .fileImporter(isPresented: $showFileImporter, allowedContentTypes: [.item]) { result in
            guard case let .success(url) = result else { return }
            Task { await sendFile(at: url) }
        }
        .onDisappear { controller.resetBeamState() }
    }

    @ViewBuilder private var beamStatus: some View {
        switch controller.beamState {
        case .idle:
            Text("Files arrive in the Downloads folder on your Mac.")
        case let .sending(progress):
            ProgressView(value: progress) {
                Text("Sending… \(Int(progress * 100))%")
            }
        case let .done(fileName):
            Label("“\(fileName)” saved to Downloads", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case let .failed(message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
        }
    }

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
