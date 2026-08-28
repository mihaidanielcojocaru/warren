//
//  DeviceActionsMenu.swift
//  Warren
//
//  The per-device action list, shared by the row's ••• menu and its right-click
//  menu so the two can never drift apart.
//

import SwiftUI

struct DeviceActionsMenu: View {
    let device: Device
    @ObservedObject var actions: DeviceActions

    /// SSH and file transfer stay enabled for offline devices — Tailscale's idea
    /// of "offline" is a heartbeat, and the user may well want to try anyway. Only
    /// a device with no address at all has nothing to connect to.
    private var hasAddress: Bool { device.connectionHost != nil }

    var body: some View {
        Button("SSH") { actions.openSSH(to: device) }
            .disabled(!hasAddress)
        Button("SSH as…") { actions.promptForUsernameThenSSH(to: device) }
            .disabled(!hasAddress)

        Divider()

        Button(actions.fileTransferTitle(for: device)) { actions.openFileTransfer(for: device) }
            .disabled(!hasAddress)
        // Taildrop needs nothing set up on either end, so it is offered wherever
        // Tailscale says the peer can take it.
        Button("Send Files…") { actions.sendFiles(to: device) }
            .disabled(!hasAddress || !device.canReceiveFiles)

        Divider()

        Button("Copy IPv4") { actions.copyIPv4(of: device) }
            .disabled(device.ipv4 == nil)
        Button("Copy Hostname") { actions.copyHostname(of: device) }
        Button("Copy SSH Command") { actions.copySSHCommand(for: device) }

        Divider()

        Button("Ping") { actions.ping(device) }
            .disabled(!hasAddress)

        if device.offersExitNode {
            Divider()
            if device.isExitNode {
                Button("Stop Using Exit Node") { actions.stopUsingExitNode() }
            } else {
                Button("Use as Exit Node") { actions.useAsExitNode(device) }
            }
        }
    }
}
