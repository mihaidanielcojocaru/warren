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
        if let override, !override.trimmingCharacters(in: .whitespaces).isEmpty {
            return isUsable(override) ? URL(fileURLWithPath: override) : nil
        }
        return candidatePaths.first(where: isUsable).map(URL.init(fileURLWithPath:))
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
