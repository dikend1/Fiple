import SwiftUI
import VisionKit

/// "Scan to Mac": live camera recognition of QR codes and printed text; a tap
/// on a recognized item puts its text on the Mac's clipboard, ready to ⌘V.
struct ScanToMacView: View {
    let controller: RemoteController

    @State private var recognized = ""
    @State private var sent = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                if DataScannerViewController.isSupported {
                    ScannerView { text in
                        recognized = text
                        sent = false
                    }
                    .ignoresSafeArea()
                } else {
                    ContentUnavailableView(
                        "Camera scanning isn't available",
                        systemImage: "camera",
                        description: Text("This device doesn't support live text scanning.")
                    )
                }

                if !recognized.isEmpty {
                    VStack(spacing: Theme.Spacing.sm) {
                        Text(recognized)
                            .font(.fiple(14, design: .monospaced))
                            .lineLimit(3)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Button {
                            Task {
                                sent = await controller.sendClipboard(text: recognized)
                                if sent { UINotificationFeedbackGenerator().notificationOccurred(.success) }
                            }
                        } label: {
                            Label(sent ? "On your Mac's clipboard — press ⌘V" : "Send to Mac Clipboard",
                                  systemImage: sent ? "checkmark" : "doc.on.clipboard")
                                .font(.fiple(15, .semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(sent ? .green : Theme.Palette.brand)
                    }
                    .padding(Theme.Spacing.lg)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
                    .padding(Theme.Spacing.lg)
                }
            }
            .navigationTitle("Scan to Mac")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }
}

/// Thin wrapper over VisionKit's live scanner, reporting the latest recognized
/// QR payload or text line. Tap-to-pick is VisionKit's own behaviour; we also
/// surface the first recognition automatically so QR codes feel instant.
private struct ScannerView: UIViewControllerRepresentable {
    let onRecognized: (String) -> Void

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(
            recognizedDataTypes: [.barcode(), .text()],
            qualityLevel: .balanced,
            recognizesMultipleItems: false,
            isHighlightingEnabled: true
        )
        scanner.delegate = context.coordinator
        try? scanner.startScanning()
        return scanner
    }

    func updateUIViewController(_ controller: DataScannerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onRecognized: onRecognized) }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let onRecognized: (String) -> Void
        init(onRecognized: @escaping (String) -> Void) { self.onRecognized = onRecognized }

        private func text(from item: RecognizedItem) -> String? {
            switch item {
            case let .barcode(code): return code.payloadStringValue
            case let .text(text): return text.transcript
            @unknown default: return nil
            }
        }

        func dataScanner(_ scanner: DataScannerViewController, didAdd added: [RecognizedItem], allItems: [RecognizedItem]) {
            if let first = added.first, let value = text(from: first) { onRecognized(value) }
        }

        func dataScanner(_ scanner: DataScannerViewController, didTapOn item: RecognizedItem) {
            if let value = text(from: item) { onRecognized(value) }
        }
    }
}
