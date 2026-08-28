//
//  TailscaleBinaryLocator.swift
//  Warren
//

import Foundation

/// Finds the `tailscale` CLI.
enum TailscaleBinaryLocator {

    /// First hit wins. The bundle path leads deliberately: `/usr/local/bin/tailscale`
    /// is usually a two-line `sh` shim that execs the very same binary, so going
    /// straight to the bundle skips a shell per poll and keeps working when the
    /// shim has not been installed.
    static let candidatePaths = [
        "/Applications/Tailscale.app/Contents/MacOS/tailscale",
        "/usr/local/bin/tailscale",
        "/opt/homebrew/bin/tailscale",
        "/usr/bin/tailscale",
    ]

    /// - Parameter override: a user-chosen path from preferences. When it is set
    ///   but unusable we return `nil` rather than silently falling back, so the
    ///   menu can say the configured path is wrong instead of quietly using
    ///   another binary.
    static func locate(override: String?) -> URL? {
        usableCandidates(override: override).first
    }

    /// Every candidate that exists and can be run, best first.
    ///
    /// More than one matters: the `tailscale` inside Tailscale.app is not a
    /// self-contained CLI on the standalone build — it brokers through the GUI
    /// app, and when that handshake fails it prints "The Tailscale GUI failed to
    /// start" **and still exits 0**. The caller needs somewhere else to turn.
    ///
    /// An explicit override is returned alone: if the user named a binary, using
    /// a different one behind their back would be worse than failing.
    static func usableCandidates(override: String?) -> [URL] {
        if let override, !override.trimmingCharacters(in: .whitespaces).isEmpty {
            return isUsable(override) ? [URL(fileURLWithPath: override)] : []
        }
        return candidatePaths.filter(isUsable).map(URL.init(fileURLWithPath:))
    }

    static func isUsable(_ path: String) -> Bool {
        var isDirectory: ObjCBool = false
        let manager = FileManager.default
        guard manager.fileExists(atPath: path, isDirectory: &isDirectory), !isDirectory.boolValue else {
            return false
        }
        return manager.isExecutableFile(atPath: path)
    }
}
