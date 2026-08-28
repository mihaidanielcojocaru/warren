//
//  Device.swift
//  Warren
//
//  The domain model the menu and the actions are written against.
//

import Foundation

/// A tailnet node in the shape the UI wants: one label, one address to connect
/// to, and the flags the actions depend on.
///
/// Values are derived once, at decode time, so no view has to know that
/// `DNSName` carries a trailing dot or that an unregistered node has an empty one.
struct Device: Identifiable, Hashable {

    /// Stable across polls, so SwiftUI rows do not churn: the CLI's `ID`, else
    /// the public key, else the `Peer` map key the node arrived under.
    let id: String

    /// Short name for the menu, with the MagicDNS suffix stripped.
    let displayName: String

    /// `HostName` as reported by the node itself.
    let hostName: String?

    /// MagicDNS name with the trailing dot removed; `nil` when the node has none.
    let dnsName: String?

    let ipv4: String?
    let ipv6: String?
    let os: DeviceOS
    let isOnline: Bool

    /// `nil` when the node has never been seen, or is online right now.
    let lastSeen: Date?

    /// True for the `Self` entry: this machine, shown in the header rather than
    /// in the device list.
    let isSelf: Bool

    /// True on the one peer currently carrying this machine's traffic.
    let isExitNode: Bool

    /// True when the peer offers itself as an exit node; gates the
    /// "Use as Exit Node" action.
    let offersExitNode: Bool

    /// True when a connection to the peer is up right now.
    let isActive: Bool

    let rxBytes: Int64
    let txBytes: Int64
    let userID: Int64?

    /// What `ssh` and `sftp` get pointed at: the MagicDNS name when there is
    /// one, else the first tailnet address. `nil` for a node with neither —
    /// the menu still lists it, but the connect actions are disabled.
    var connectionHost: String? {
        dnsName ?? ipv4 ?? ipv6
    }
}

extension Device {

    /// - Parameters:
    ///   - nodeKey: the key this peer arrived under in the `Peer` map, used as a
    ///     last-resort identity when the payload carries neither `ID` nor `PublicKey`.
    ///   - magicDNSSuffix: tailnet suffix to strip from the display name.
    init(peer: PeerStatus, nodeKey: String, magicDNSSuffix: String?, isSelf: Bool) {
        let dnsName = Device.strippingTrailingDot(peer.dnsName)
        let addresses = peer.tailscaleIPs
        let ipv4 = addresses.first { !$0.contains(":") }
        let ipv6 = addresses.first { $0.contains(":") }

        self.init(
            id: peer.id ?? peer.publicKey ?? nodeKey,
            displayName: Device.displayName(
                dnsName: dnsName,
                hostName: peer.hostName,
                magicDNSSuffix: magicDNSSuffix,
                fallbackAddress: ipv4 ?? ipv6
            ),
            hostName: peer.hostName,
            dnsName: dnsName,
            ipv4: ipv4,
            ipv6: ipv6,
            os: DeviceOS(wireValue: peer.os),
            isOnline: peer.online,
            lastSeen: peer.lastSeen,
            isSelf: isSelf,
            isExitNode: peer.exitNode,
            offersExitNode: peer.exitNodeOption,
            isActive: peer.active,
            rxBytes: peer.rxBytes,
            txBytes: peer.txBytes,
            userID: peer.userID
        )
    }

    /// `nas.tailnet-example.ts.net.` → `nas.tailnet-example.ts.net`.
    /// An empty or whitespace-only name becomes `nil`.
    static func strippingTrailingDot(_ raw: String?) -> String? {
        guard var name = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty else {
            return nil
        }
        while name.hasSuffix(".") { name.removeLast() }
        return name.isEmpty ? nil : name
    }

    /// `nas.tailnet-example.ts.net` → `nas`.
    ///
    /// Prefers the DNS name over `HostName` because that is the name the tailnet
    /// agrees on — two machines can report the same `HostName`, but MagicDNS
    /// de-duplicates them (`nas-1`, `nas-2`). Falls back to `HostName`, then to an
    /// address, because the menu always needs something to render.
    static func displayName(
        dnsName: String?,
        hostName: String?,
        magicDNSSuffix: String?,
        fallbackAddress: String?
    ) -> String {
        if let dnsName {
            // Strip the tailnet's own suffix when it matches; otherwise fall back
            // to the first label, which is the right answer for a node shared in
            // from another tailnet (`node.other-tailnet.ts.net`).
            if let suffix = magicDNSSuffix, !suffix.isEmpty,
               dnsName.hasSuffix("." + suffix) {
                let short = String(dnsName.dropLast(suffix.count + 1))
                if !short.isEmpty { return short }
            }
            if let firstLabel = dnsName.split(separator: ".").first, !firstLabel.isEmpty {
                return String(firstLabel)
            }
            return dnsName
        }
        if let hostName, !hostName.isEmpty { return hostName }
        if let fallbackAddress { return fallbackAddress }
        return "Unnamed device"
    }
}

/// Operating system as reported by the node.
///
/// The CLI emits Go's `GOOS` for most platforms but Apple's marketing names for
/// Apple ones, so matching is case-insensitive. An unrecognized value is kept
/// verbatim: it still renders, just with a generic glyph.
enum DeviceOS: Hashable {
    case macOS
    case iOS
    case tvOS
    case linux
    case windows
    case android
    case freeBSD
    case openBSD
    case unknown(String)

    init(wireValue: String?) {
        switch (wireValue ?? "").lowercased() {
        case "macos": self = .macOS
        case "ios": self = .iOS
        case "tvos": self = .tvOS
        case "linux": self = .linux
        case "windows": self = .windows
        case "android": self = .android
        case "freebsd": self = .freeBSD
        case "openbsd": self = .openBSD
        default: self = .unknown(wireValue ?? "")
        }
    }

    var displayName: String {
        switch self {
        case .macOS: return "macOS"
        case .iOS: return "iOS"
        case .tvOS: return "tvOS"
        case .linux: return "Linux"
        case .windows: return "Windows"
        case .android: return "Android"
        case .freeBSD: return "FreeBSD"
        case .openBSD: return "OpenBSD"
        case .unknown(let value): return value.isEmpty ? "Unknown" : value
        }
    }
}
