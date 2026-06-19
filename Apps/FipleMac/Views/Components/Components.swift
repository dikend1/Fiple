import AppKit
import FipleKit
import SwiftUI

/// A rounded icon tile — soft accent-tinted background with either a real logo
/// image or an SF Symbol glyph. Reused on cards, lists and the Recent feed.
struct IconTile: View {
    let iconImageData: Data?
    let systemName: String
    let colorHex: String
    var size: CGFloat = 44
    var cornerRadius: CGFloat = Theme.Radius.tile

    var body: some View {
        let accent = Accent(hex: colorHex)
        Group {
            if let iconImageData, let image = NSImage(data: iconImageData) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .padding(size * 0.16)
            } else {
                Image(systemName: systemName)
                    .font(.system(size: size * 0.42, weight: .semibold))
                    .foregroundStyle(accent.glyph)
            }
        }
        .frame(width: size, height: size)
        .background(accent.iconBackground, in: RoundedRectangle(cornerRadius: cornerRadius))
    }
}

/// Page header: big title, supporting line, and an optional trailing accessory.
struct PageHeader<Trailing: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text(title).font(Theme.Font.largeTitle)
                Text(subtitle).font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
            trailing
        }
    }
}

extension PageHeader where Trailing == EmptyView {
    init(title: String, subtitle: String) {
        self.init(title: title, subtitle: subtitle) { EmptyView() }
    }
}

/// The "iPhone 15 Pro • Connected" status chip from the top-right of the design.
struct DeviceChip: View {
    let server: ServerController

    var body: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Image(systemName: "iphone.gen3")
                .font(.system(size: 16))
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 1) {
                Text(name).font(.system(size: 13, weight: .semibold))
                HStack(spacing: 5) {
                    Circle()
                        .fill(server.status == .connected ? Theme.Palette.connected : .secondary)
                        .frame(width: 6, height: 6)
                    Text(statusText)
                        .font(.system(size: 11))
                        .foregroundStyle(server.status == .connected ? Theme.Palette.connected : .secondary)
                }
            }
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.sm)
        .fipleCard(cornerRadius: Theme.Radius.control)
    }

    private var name: String { server.status == .connected ? "iPhone" : "No device" }
    private var statusText: String {
        switch server.status {
        case .connected: "Connected"
        case .advertising: "Waiting…"
        case .idle: "Off"
        }
    }
}

/// A labelled stat column (e.g. "4 / Apps") used on workspace cards.
struct StatColumn: View {
    let value: Int
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(value)").font(Theme.Font.statNumber)
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
    }
}

/// A titled content panel (Recent / Focus blocks) with an optional trailing
/// "View all" action in its header.
struct Panel<Content: View>: View {
    let title: String
    let icon: String
    var actionTitle: String?
    var action: (() -> Void)?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            HStack {
                Label(title, systemImage: icon)
                    .font(.system(size: 15, weight: .semibold))
                Spacer()
                if let actionTitle, let action {
                    Button(actionTitle, action: action)
                        .buttonStyle(.plain)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
            }
            content
        }
        .padding(Theme.Spacing.lg)
        .fipleCard()
    }
}
