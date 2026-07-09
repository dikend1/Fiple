import SwiftUI

/// The share card: a compact bottom panel that narrates the send — finding the
/// Mac → progress → done — and dismisses itself two beats after success.
struct ShareView: View {
    let attachments: [NSItemProvider]
    let onFinish: () -> Void
    let onCancel: () -> Void

    @State private var sender = ShareSender()

    private let brand = Color(red: 0.18, green: 0.64, blue: 0.31)

    var body: some View {
        VStack {
            Spacer()
            card
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
        }
        .background(Color.black.opacity(0.001)) // keep touches inside the card
        .task {
            await sender.run(attachments: attachments)
            if isDone {
                try? await Task.sleep(for: .seconds(1.2))
                onFinish()
            }
        }
    }

    private var isDone: Bool {
        switch sender.phase {
        case .doneFile, .doneClipboard: true
        default: false
        }
    }

    private var card: some View {
        VStack(spacing: 16) {
            HStack {
                Text("Send to Mac")
                    .font(.system(size: 17, weight: .semibold))
                Spacer()
                if !isDone {
                    Button("Cancel", action: onCancel)
                        .font(.system(size: 15))
                }
            }

            statusRow

            if !sender.itemLabel.isEmpty {
                Text(sender.itemLabel)
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if case .failed = sender.phase {
                Button("Done", action: onCancel)
                    .font(.system(size: 16, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color(.secondarySystemFill), in: RoundedRectangle(cornerRadius: 12))
            }
        }
        .padding(20)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    @ViewBuilder private var statusRow: some View {
        HStack(spacing: 12) {
            switch sender.phase {
            case .resolving, .searching:
                ProgressView()
                Text(sender.phase == .resolving ? "Preparing…" : "Looking for your Mac…")
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
            case let .sending(progress):
                ProgressView(value: progress)
                Text("\(Int(progress * 100))%")
                    .font(.system(size: 14, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
            case let .doneFile(name):
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(brand)
                Text("“\(name)” saved to Downloads")
                    .font(.system(size: 15, weight: .medium))
            case .doneClipboard:
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(brand)
                Text("On your Mac's clipboard — press ⌘V")
                    .font(.system(size: 15, weight: .medium))
            case let .failed(message):
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(.orange)
                Text(message)
                    .font(.system(size: 14))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(.easeOut(duration: 0.2), value: sender.phase)
    }
}
