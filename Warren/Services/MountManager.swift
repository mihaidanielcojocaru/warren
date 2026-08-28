//
//  MountManager.swift
//  Warren
//
//  File transfer. Finder cannot mount sftp://, so this does not try.
//

import AppKit
import Foundation

enum MountError: LocalizedError {
    case sshfsUnavailable
    case invalidTarget(String)
    case mountFailed(String)
    case unmountFailed(String)

    var errorDescription: String? {
        switch self {
        case .sshfsUnavailable:
            return "sshfs and macFUSE are not installed."
        case .invalidTarget(let target):
            return "\"\(target)\" is not a valid host name or address."
        case .mountFailed(let reason):
            return reason.isEmpty ? "The remote folder could not be mounted." : reason
        case .unmountFailed(let reason):
            return reason.isEmpty ? "The volume could not be unmounted." : reason
        }
    }
}

protocol MountManaging {
    /// True only when both halves are present: the binary and the kernel extension.
    var isSSHFSAvailable: Bool { get }

    func mountPointURL(for device: Device) -> URL
    func isMounted(_ device: Device) -> Bool
    func mount(device: Device, username: String, host: String) async throws
    func unmount(device: Device) async throws

    /// True when the peer has something listening on the SMB port.
    func isSMBAvailable(host: String) -> Bool

    /// Hands `smb://host` to the Finder, which mounts it natively — no macFUSE,
    /// no third-party client. Returns false if the Finder refused the URL.
    func openSMB(host: String) -> Bool

    /// Hands `sftp://user@host` to whichever client is registered — Cyberduck,
    /// Transmit, Mountain Duck. Returns false when nothing claims the scheme.
    func openInExternalClient(username: String, host: String) -> Bool

    /// The command to put on the clipboard when there is nothing else to offer.
    func sftpCommand(username: String, host: String) -> String
}

struct MountManager: MountManaging {

    /// macFUSE installs its file system bundle here; sshfs without it cannot mount.
    private static let macFUSEPath = "/Library/Filesystems/macfuse.fs"

    private static let sshfsCandidatePaths = [
        "/usr/local/bin/sshfs",
        "/opt/homebrew/bin/sshfs",
        "/usr/bin/sshfs",
    ]

    private let runner: ProcessRunning
    private let fileManager = FileManager.default

    init(runner: ProcessRunning = ProcessRunner()) {
        self.runner = runner
    }

    // MARK: - Availability

    var isSSHFSAvailable: Bool {
        sshfsURL != nil && fileManager.fileExists(atPath: Self.macFUSEPath)
    }

    private var sshfsURL: URL? {
        if let known = Self.sshfsCandidatePaths.first(where: TailscaleBinaryLocator.isUsable) {
            return URL(fileURLWithPath: known)
        }
        // Then anything on PATH, for a Nix or MacPorts install.
        let path = ProcessInfo.processInfo.environment["PATH"] ?? ""
        for directory in path.split(separator: ":") {
            let candidate = URL(fileURLWithPath: String(directory)).appendingPathComponent("sshfs")
            if TailscaleBinaryLocator.isUsable(candidate.path) { return candidate }
        }
        return nil
    }

    // MARK: - Mount points

    /// `~/Warren Mounts/<device>`, one directory per device.
    static var mountsDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Warren Mounts")
    }

    func mountPointURL(for device: Device) -> URL {
        // The display name is the only user-facing identifier, but it reaches the
        // file system, so keep it to something a path can hold.
        let safeName = device.displayName
            .components(separatedBy: CharacterSet(charactersIn: "/:\0"))
            .joined(separator: "-")
        return Self.mountsDirectory.appendingPathComponent(safeName.isEmpty ? device.id : safeName)
    }

    func isMounted(_ device: Device) -> Bool {
        let target = mountPointURL(for: device).standardizedFileURL.path
        let volumes = fileManager.mountedVolumeURLs(includingResourceValuesForKeys: nil, options: []) ?? []
        return volumes.contains { $0.standardizedFileURL.path == target }
    }

    // MARK: - Mounting

    func mount(device: Device, username: String, host: String) async throws {
        guard let sshfs = sshfsURL, fileManager.fileExists(atPath: Self.macFUSEPath) else {
            throw MountError.sshfsUnavailable
        }
        guard ConnectionTarget.isValidHost(host), ConnectionTarget.isValidUsername(username) else {
            throw MountError.invalidTarget(host)
        }

        let mountPoint = mountPointURL(for: device)
        try? fileManager.createDirectory(at: mountPoint, withIntermediateDirectories: true)

        // `user@host:` with an empty path means the remote home directory.
        let result = try runner.run(sshfs, arguments: [
            "\(username)@\(host):",
            mountPoint.path,
            "-o", "volname=\(device.displayName)",
            "-o", "reconnect",
            "-o", "defer_permissions",
            "-o", "noappledouble",
        ], timeout: 30)

        guard result.didSucceed else {
            try? fileManager.removeItem(at: mountPoint)
            throw MountError.mountFailed(result.standardError.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        NSWorkspace.shared.activateFileViewerSelecting([mountPoint])
    }

    func unmount(device: Device) async throws {
        let mountPoint = mountPointURL(for: device)
        let result = try runner.run(
            URL(fileURLWithPath: "/sbin/umount"),
            arguments: [mountPoint.path],
            timeout: 15
        )
        guard result.didSucceed else {
            throw MountError.unmountFailed(result.standardError.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        // The empty directory is ours; tidy it away, but only if it is empty.
        if let contents = try? fileManager.contentsOfDirectory(atPath: mountPoint.path), contents.isEmpty {
            try? fileManager.removeItem(at: mountPoint)
        }
    }

    // MARK: - SMB

    /// The Finder speaks SMB natively, so where a peer serves it this is by far
    /// the least friction: no macFUSE, no extra app, and it mounts read-write.
    func isSMBAvailable(host: String) -> Bool {
        PortProbe.isOpen(host: host, port: 445)
    }

    /// Deliberately without a user name. The SMB login on a NAS is usually not
    /// the SSH one, and the Finder remembers the right credentials in the
    /// keychain after the first connection anyway.
    func openSMB(host: String) -> Bool {
        guard ConnectionTarget.isValidHost(host),
              let url = URL(string: "smb://\(host)") else { return false }
        return NSWorkspace.shared.open(url)
    }

    // MARK: - Fallbacks

    func openInExternalClient(username: String, host: String) -> Bool {
        guard ConnectionTarget.isValidHost(host), ConnectionTarget.isValidUsername(username),
              let url = URL(string: "sftp://\(username)@\(host)") else { return false }
        // Nothing registered for sftp:// means no third-party client is installed.
        guard NSWorkspace.shared.urlForApplication(toOpen: url) != nil else { return false }
        return NSWorkspace.shared.open(url)
    }

    func sftpCommand(username: String, host: String) -> String {
        "sftp \(username)@\(host)"
    }
}
