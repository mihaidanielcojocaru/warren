//
//  DeviceActions.swift
//  Warren
//
//  Everything a menu row can do. Views call into this; it owns the side effects.
//

import Combine
import AppKit
import Foundation

/// A ping in flight or finished, shown in the popover.
struct PingSession: Identifiable, Equatable {
    let id: String
    let deviceName: String
    var output: String?
    var failure: String?

    var isRunning: Bool { output == nil && failure == nil }
}

@MainActor
final class DeviceActions: ObservableObject {

    /// Non-nil while a ping popover should be on screen.
    @Published var pingSession: PingSession?

    /// Set by the composition root so an exit-node change shows up immediately.
    var requestRefresh: () -> Void = {}

    private let client: TailscaleClienting
    private let terminal: TerminalLaunching
    private let mounts: MountManaging
    private let preferences: Preferences

    init(
        client: TailscaleClienting,
        terminal: TerminalLaunching,
        mounts: MountManaging,
        preferences: Preferences
    ) {
        self.client = client
        self.terminal = terminal
        self.mounts = mounts
        self.preferences = preferences
    }

    // MARK: - Default click

    func performDefaultAction(on device: Device) {
        switch preferences.clickAction {
        case .ssh: openSSH(to: device)
        case .fileTransfer: openFileTransfer(for: device)
        case .copyIPv4: copyIPv4(of: device)
        }
    }

    // MARK: - SSH

    func openSSH(to device: Device, username: String? = nil) {
        guard let host = device.connectionHost else {
            return AlertPresenter.notify(
                title: "\(device.displayName) has no address",
                message: "Tailscale reports neither a MagicDNS name nor a tailnet IP for this device."
            )
        }
        let login = username ?? preferences.username(for: device)
        guard ConnectionTarget.isValidUsername(login) else {
            return AlertPresenter.notify(
                title: "\"\(login)\" is not a valid user name",
                message: "Change it in Warren's settings, or use SSH as… for a one-off login."
            )
        }
        guard ConnectionTarget.isValidHost(host) else {
            return AlertPresenter.notify(title: "\"\(host)\" is not a valid host name")
        }

        // An argument vector, never a shell string. The AppleScript terminals
        // quote it back into one; see TerminalLauncher.
        run(command: ["ssh", "\(login)@\(host)"])
    }

    func promptForUsernameThenSSH(to device: Device) {
        let suggestion = preferences.username(for: device)
        guard let username = AlertPresenter.promptForText(
            title: "Connect to \(device.displayName) as",
            message: "This is used once and is not saved.",
            defaultValue: suggestion
        ) else { return }
        openSSH(to: device, username: username)
    }

    private func run(command: [String]) {
        Task {
            do {
                let app = try terminal.resolveTerminal(configured: preferences.terminalApp)
                try await terminal.launch(command: command, using: app)
            } catch {
                AlertPresenter.show(error: error)
            }
        }
    }

    // MARK: - File transfer

    func fileTransferTitle(for device: Device) -> String {
        guard mounts.isSSHFSAvailable else { return "Open in Finder (SFTP)…" }
        return mounts.isMounted(device) ? "Unmount \(device.displayName)" : "Mount with sshfs"
    }

    func openFileTransfer(for device: Device) {
        guard let host = device.connectionHost else {
            return AlertPresenter.notify(title: "\(device.displayName) has no address")
        }
        let login = preferences.username(for: device)

        if mounts.isSSHFSAvailable {
            Task { await toggleMount(device: device, username: login, host: host) }
            return
        }

        // No macFUSE: hand it to whatever SFTP client is registered.
        if mounts.openInExternalClient(username: login, host: host) { return }

        // Nothing can open it. Say why, and leave something usable behind.
        let command = mounts.sftpCommand(username: login, host: host)
        let copyIt = AlertPresenter.show(
            title: "No file transfer app is available",
            message: """
            The Finder cannot open sftp:// connections. Install macFUSE and sshfs to mount \
            \(device.displayName) as a volume, or an SFTP client such as Cyberduck or Transmit.

            In the meantime you can run:
            \(command)
            """,
            style: .informational,
            buttons: ["Copy Command", "Cancel"]
        )
        if copyIt { Clipboard.copy(command) }
    }

    private func toggleMount(device: Device, username: String, host: String) async {
        do {
            if mounts.isMounted(device) {
                try await mounts.unmount(device: device)
            } else {
                try await mounts.mount(device: device, username: username, host: host)
            }
        } catch {
            AlertPresenter.show(error: error)
        }
    }

    // MARK: - Clipboard

    func copyIPv4(of device: Device) {
        guard let ipv4 = device.ipv4 else {
            return AlertPresenter.notify(title: "\(device.displayName) has no IPv4 address")
        }
        Clipboard.copy(ipv4)
    }

    func copyHostname(of device: Device) {
        Clipboard.copy(device.dnsName ?? device.displayName)
    }

    func copySSHCommand(for device: Device) {
        guard let host = device.connectionHost else {
            return AlertPresenter.notify(title: "\(device.displayName) has no address")
        }
        Clipboard.copy("ssh \(preferences.username(for: device))@\(host)")
    }

    // MARK: - Ping

    func ping(_ device: Device) {
        guard let host = device.connectionHost else {
            return AlertPresenter.notify(title: "\(device.displayName) has no address")
        }
        pingSession = PingSession(id: device.id, deviceName: device.displayName)

        Task {
            do {
                let output = try await offMain { try self.client.ping(host: host) }
                guard pingSession?.id == device.id else { return }
                pingSession?.output = output
            } catch {
                guard pingSession?.id == device.id else { return }
                pingSession?.failure = (error as? LocalizedError)?.errorDescription
                    ?? error.localizedDescription
            }
        }
    }

    func dismissPing() {
        pingSession = nil
    }

    // MARK: - Exit node

    func useAsExitNode(_ device: Device) {
        guard let address = device.ipv4 ?? device.ipv6 else {
            return AlertPresenter.notify(title: "\(device.displayName) has no address to route through")
        }
        changeExitNode(to: address, description: "route traffic through \(device.displayName)")
    }

    func stopUsingExitNode() {
        changeExitNode(to: nil, description: "stop using an exit node")
    }

    private func changeExitNode(to address: String?, description: String) {
        Task {
            do {
                try await offMain { try self.client.setExitNode(address: address) }
                requestRefresh()
            } catch {
                // `tailscale set` can need an authorisation the user declined, and
                // failing silently here would look like the click did nothing.
                let reason = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                AlertPresenter.show(
                    title: "Warren could not \(description)",
                    message: """
                    \(reason)

                    Changing the exit node may need an administrator password. \
                    You can also change it from the Tailscale menu bar app.
                    """
                )
            }
        }
    }

    // MARK: - Plumbing

    /// The client's calls block on a subprocess, so they never run on the main actor.
    private func offMain<T>(_ work: @escaping () throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(with: Result { try work() })
            }
        }
    }
}
