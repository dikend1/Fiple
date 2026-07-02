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
            // A raised dark tile with a white "F" — the flat dark logo asset
            // blended into the dark sidebar, so the mark is drawn white to match
            // the menu-bar icon and stay legible here.
            RoundedRectangle(cornerRadius: Theme.Radius.tile, style: .continuous)
                .fill(Theme.Palette.sidebarRaised)
                .frame(width: 40, height: 40)
                .overlay { FipleMark(size: 19, style: .white) }
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.tile, style: .continuous)
                        .strokeBorder(.white.opacity(0.14))
                )
            Text("Fiple")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(Theme.Palette.sidebarText)
        }
    }

    private var navigation: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
            ForEach(Array(SidebarSection.groups.enumerated()), id: \.offset) { _, group in
                VStack(spacing: Theme.Spacing.xs) {
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
                Text(connectionLabel)
                    .font(.system(size: 11))
                    .foregroundStyle(server.status == .connected ? Theme.Palette.connected : Theme.Palette.sidebarSecondary)
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
            .padding(.vertical, 9)
            .padding(.horizontal, Theme.Spacing.md)
            .background(rowBackground)
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
