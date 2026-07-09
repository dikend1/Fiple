import FipleKit
import SwiftUI

/// The dark brand sidebar: logo, grouped navigation, and a footer showing the
/// connected device. Styled to stay dark regardless of system appearance.
struct SidebarView: View {
    @Binding var section: SidebarSection
    let server: ServerController

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            brand
                .padding(.top, 36) // clear the overlaid traffic lights
                .padding(.horizontal, Theme.Spacing.lg)
                .padding(.bottom, Theme.Spacing.xl)

            navigation

            Spacer(minLength: Theme.Spacing.lg)

            footer
                .padding(Theme.Spacing.md)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.Palette.sidebar)
        .environment(\.colorScheme, .dark)
    }

    private var brand: some View {
        HStack(spacing: Theme.Spacing.md) {
            // The real app icon (dark squircle + white F), same as the menu-bar
            // popover — the previous drawn mark wasn't the actual brand icon.
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable()
                .interpolation(.high)
                .frame(width: 40, height: 40)
            Text("Fiple")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(Theme.Palette.sidebarText)
        }
    }

    private var navigation: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            ForEach(Array(SidebarSection.groups.enumerated()), id: \.offset) { index, group in
                if index > 0 {
                    // A hairline anchors each group; the old bare gaps left the
                    // items floating in the dark.
                    Rectangle()
                        .fill(Color.white.opacity(0.07))
                        .frame(height: 1)
                        .padding(.horizontal, Theme.Spacing.sm)
                }
                if let label = Self.groupLabels[index] {
                    Text(label)
                        .font(.system(size: 10, weight: .semibold))
                        .tracking(1.4)
                        .foregroundStyle(Theme.Palette.sidebarSecondary)
                        .padding(.horizontal, Theme.Spacing.md)
                        .padding(.top, 2)
                }
                VStack(spacing: 2) {
                    ForEach(group) { item in
                        SidebarRow(item: item, isSelected: section == item) {
                            section = item
                        }
                    }
                }
            }
        }
        .padding(.horizontal, Theme.Spacing.md)
    }

    /// Only the Tools group carries a label — it names a concept that isn't
    /// self-evident; the navigation and system groups explain themselves.
    private static let groupLabels: [Int: String] = [2: "TOOLS"]

    private var footer: some View {
        HStack(spacing: Theme.Spacing.md) {
            Image(systemName: "iphone.gen3")
                .font(.system(size: 18))
                .foregroundStyle(Theme.Palette.sidebarText)
                .frame(width: 34, height: 34)
                .background(Theme.Palette.sidebarRaised, in: RoundedRectangle(cornerRadius: Theme.Radius.control))
            VStack(alignment: .leading, spacing: 1) {
                Text(server.status == .connected ? "iPhone" : "No device")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.Palette.sidebarText)
                HStack(spacing: 5) {
                    Circle()
                        .fill(server.status == .connected ? Theme.Palette.connected : Color.orange)
                        .frame(width: 6, height: 6)
                    Text(connectionLabel)
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.Palette.sidebarSecondary)
                }
            }
            Spacer()
        }
        .padding(Theme.Spacing.sm)
        .background(Theme.Palette.sidebarRaised, in: RoundedRectangle(cornerRadius: Theme.Radius.control))
    }

    private var connectionLabel: String {
        switch server.status {
        case .connected: "Connected"
        case .advertising: "Waiting…"
        case .idle: "Off"
        }
    }
}

/// A single navigation row with the selected-state pill from the design.
private struct SidebarRow: View {
    let item: SidebarSection
    let isSelected: Bool
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: Theme.Spacing.md) {
                Image(systemName: item.icon)
                    .font(.system(size: 15))
                    .frame(width: 22)
                Text(item.title)
                    .font(.system(size: 14, weight: isSelected ? .semibold : .regular))
                Spacer()
            }
            .foregroundStyle(isSelected ? Theme.Palette.brand : Theme.Palette.sidebarText)
            .padding(.vertical, 8)
            .padding(.horizontal, Theme.Spacing.md)
            .background(rowBackground)
            // The selected pill gets a small brand accent bar — a stronger
            // "you are here" than tinted text alone.
            .overlay(alignment: .leading) {
                if isSelected {
                    Capsule()
                        .fill(Theme.Palette.brand)
                        .frame(width: 3, height: 16)
                        .offset(x: 4)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }

    @ViewBuilder private var rowBackground: some View {
        if isSelected {
            RoundedRectangle(cornerRadius: Theme.Radius.control)
                .fill(Theme.Palette.sidebarRaised)
        } else if hovering {
            RoundedRectangle(cornerRadius: Theme.Radius.control)
                .fill(Color.white.opacity(0.04))
        }
    }
}
