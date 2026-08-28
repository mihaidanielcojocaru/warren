//
//  DeviceRowView.swift
//  Warren
//

import SwiftUI

struct DeviceRowView: View {
    let device: Device
    @ObservedObject var actions: DeviceActions

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: device.os.symbolName)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 0) {
                Text(device.displayName)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if !device.isOnline {
                    Text(RelativeTime.lastSeen(device.lastSeen))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer(minLength: 4)

            if device.isExitNode {
                Image(systemName: "arrow.triangle.branch")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .help("Exit node")
            }

            // Revealed on hover rather than sprung open by it: a menu that opens
            // itself under a moving cursor is hostile inside a panel.
            Menu {
                DeviceActionsMenu(device: device, actions: actions)
            } label: {
                Image(systemName: "ellipsis")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .frame(width: 16)
            .opacity(isHovering ? 1 : 0)

            Circle()
                .fill(device.isOnline ? Color.green : Color.secondary.opacity(0.35))
                .frame(width: 6, height: 6)
        }
        .menuRowInsets()
        .background(
            RoundedRectangle(cornerRadius: 5)
                .fill(isHovering ? Color.primary.opacity(0.08) : Color.clear)
        )
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .onTapGesture { actions.performDefaultAction(on: device) }
        .contextMenu {
            DeviceActionsMenu(device: device, actions: actions)
        }
        .popover(isPresented: pingPresentation, arrowEdge: .trailing) {
            if let session = actions.pingSession {
                PingPopoverView(session: session, onDismiss: actions.dismissPing)
            }
        }
        .help(device.dnsName ?? device.ipv4 ?? device.displayName)
    }

    /// One popover, owned by whichever row is being pinged.
    private var pingPresentation: Binding<Bool> {
        Binding(
            get: { actions.pingSession?.id == device.id },
            set: { isPresented in
                if !isPresented, actions.pingSession?.id == device.id { actions.dismissPing() }
            }
        )
    }
}
