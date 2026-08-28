//
//  TailscaleStatus.swift
//  Warren
//
//  Wire models for `tailscale status --json`.
//

import Foundation

/// The subset of `tailscale status --json` that Warren needs.
///
/// Key names follow the CLI's Go types (`ipnstate.Status`, `ipnstate.PeerStatus`),
/// which capitalise their JSON keys. Nothing here is required: every property is
/// optional or has a default, and decoding is routed through `LossyDecoding` so a
/// schema change downgrades the menu rather than breaking it.
///
/// The same payload arrives two ways: from `tailscale status --json`, and from the
/// daemon's loopback API, which is what Warren normally polls. See
/// `TailscaleLocalAPI`.
struct TailscaleStatus: Decodable, Equatable {

    /// CLI version string, e.g. `1.102.3-t9329c3677-ga522f65e9`.
    var version: String?

    /// Drives every top-level menu state. See `TailnetState`.
    var backendState: BackendState

    /// Set while the backend is waiting for the user to authenticate.
    var authURL: String?

    /// This machine's addresses, IPv4 first.
    var tailscaleIPs: [String]

    /// e.g. `tailnet-example.ts.net`, without a leading or trailing dot.
    var magicDNSSuffix: String?

    var currentTailnet: TailnetInfo?

    /// Warnings the daemon wants surfaced. Empty when healthy.
    var health: [String]

    /// This machine. Absent before the backend has a node key.
    var selfNode: PeerStatus?

    /// Every other node, keyed by node public key.
    var peers: [String: PeerStatus]

    /// Node owners, keyed by the stringified `UserID` found on a `PeerStatus`.
    var users: [String: UserProfile]

    private enum CodingKeys: String, CodingKey {
        case version = "Version"
        case backendState = "BackendState"
        case authURL = "AuthURL"
        case tailscaleIPs = "TailscaleIPs"
        case magicDNSSuffix = "MagicDNSSuffix"
        case currentTailnet = "CurrentTailnet"
        case health = "Health"
        case selfNode = "Self"
        case peers = "Peer"
        case users = "User"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = container.lossyNonEmptyString(.version)
        backendState = container.lossy(BackendState.self, .backendState) ?? .unrecognized("")
        authURL = container.lossyNonEmptyString(.authURL)
        tailscaleIPs = container.lossyArray(String.self, .tailscaleIPs)
        magicDNSSuffix = container.lossyNonEmptyString(.magicDNSSuffix)
        currentTailnet = container.lossy(TailnetInfo.self, .currentTailnet)
        health = container.lossyArray(String.self, .health)
        selfNode = container.lossy(PeerStatus.self, .selfNode)
        peers = container.lossyDictionary(PeerStatus.self, .peers)
        users = container.lossyDictionary(UserProfile.self, .users)
    }
}

/// `ipn.State` as rendered by the CLI. An unrecognized value is carried through
/// verbatim so a state added by a future release shows up in diagnostics instead
/// of being silently read as "running".
enum BackendState: Hashable {
    case noState
    case needsMachineAuth
    case needsLogin
    case stopped
    case starting
    case running
    case inUseOtherUser
    case unrecognized(String)

    init(wireValue: String) {
        switch wireValue {
        case "NoState": self = .noState
        case "NeedsMachineAuth": self = .needsMachineAuth
        case "NeedsLogin": self = .needsLogin
        case "Stopped": self = .stopped
        case "Starting": self = .starting
        case "Running": self = .running
        case "InUseOtherUser": self = .inUseOtherUser
        default: self = .unrecognized(wireValue)
        }
    }

    var wireValue: String {
        switch self {
        case .noState: return "NoState"
        case .needsMachineAuth: return "NeedsMachineAuth"
        case .needsLogin: return "NeedsLogin"
        case .stopped: return "Stopped"
        case .starting: return "Starting"
        case .running: return "Running"
        case .inUseOtherUser: return "InUseOtherUser"
        case .unrecognized(let value): return value
        }
    }
}

extension BackendState: Decodable {
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.init(wireValue: (try? container.decode(String.self)) ?? "")
    }
}

/// A single node — either the `Self` entry or one value of the `Peer` map.
struct PeerStatus: Decodable, Equatable {

    /// The CLI's `ID`: a stable node identifier that survives key rotation.
    var id: String?

    var publicKey: String?

    /// Short name as the node reports it, e.g. `nas`.
    var hostName: String?

    /// Fully qualified MagicDNS name *including* the trailing dot, e.g.
    /// `nas.tailnet-example.ts.net.`. Empty for a node without MagicDNS.
    var dnsName: String?

    /// Go's `GOOS` for most platforms, but Apple's marketing names for Apple
    /// ones: `linux`, `windows`, `android`, `macOS`, `iOS`, `tvOS`.
    var os: String?

    /// Owner, resolvable against `TailscaleStatus.users`.
    var userID: Int64?

    /// Node addresses, IPv4 first.
    var tailscaleIPs: [String]

    var online: Bool

    /// Absent, or Go's zero time, for a node that has never been seen.
    var lastSeen: Date?

    /// True on the one peer currently carrying this machine's traffic.
    var exitNode: Bool

    /// True when the peer advertises itself as usable as an exit node.
    var exitNodeOption: Bool

    /// True when there is an active connection to the peer right now.
    var active: Bool

    var rxBytes: Int64
    var txBytes: Int64

    private enum CodingKeys: String, CodingKey {
        case id = "ID"
        case publicKey = "PublicKey"
        case hostName = "HostName"
        case dnsName = "DNSName"
        case os = "OS"
        case userID = "UserID"
        case tailscaleIPs = "TailscaleIPs"
        case online = "Online"
        case lastSeen = "LastSeen"
        case exitNode = "ExitNode"
        case exitNodeOption = "ExitNodeOption"
        case active = "Active"
        case rxBytes = "RxBytes"
        case txBytes = "TxBytes"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = container.lossyNonEmptyString(.id)
        publicKey = container.lossyNonEmptyString(.publicKey)
        hostName = container.lossyNonEmptyString(.hostName)
        dnsName = container.lossyNonEmptyString(.dnsName)
        os = container.lossyNonEmptyString(.os)
        userID = container.lossy(Int64.self, .userID)
        tailscaleIPs = container.lossyArray(String.self, .tailscaleIPs)
        online = container.lossyBool(.online)
        lastSeen = container.lossyDate(.lastSeen)
        exitNode = container.lossyBool(.exitNode)
        exitNodeOption = container.lossyBool(.exitNodeOption)
        active = container.lossyBool(.active)
        rxBytes = container.lossyInt64(.rxBytes)
        txBytes = container.lossyInt64(.txBytes)
    }
}

/// The `CurrentTailnet` object: which tailnet this machine is currently joined to.
struct TailnetInfo: Decodable, Equatable {

    /// Human-readable tailnet name, e.g. `example.com`.
    var name: String?

    var magicDNSSuffix: String?
    var magicDNSEnabled: Bool

    private enum CodingKeys: String, CodingKey {
        case name = "Name"
        case magicDNSSuffix = "MagicDNSSuffix"
        case magicDNSEnabled = "MagicDNSEnabled"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = container.lossyNonEmptyString(.name)
        magicDNSSuffix = container.lossyNonEmptyString(.magicDNSSuffix)
        magicDNSEnabled = container.lossyBool(.magicDNSEnabled)
    }
}

/// An entry of the top-level `User` map.
struct UserProfile: Decodable, Equatable {
    var id: Int64?
    var loginName: String?
    var displayName: String?

    private enum CodingKeys: String, CodingKey {
        case id = "ID"
        case loginName = "LoginName"
        case displayName = "DisplayName"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = container.lossy(Int64.self, .id)
        loginName = container.lossyNonEmptyString(.loginName)
        displayName = container.lossyNonEmptyString(.displayName)
    }
}

// MARK: - In-memory construction
//
// Declaring `init(from:)` in the type body suppresses the memberwise initializer,
// so these stand in for it — used by the fake `TailscaleClient` in tests and by
// SwiftUI previews, neither of which should have to round-trip through JSON.

extension TailscaleStatus {
    init(
        version: String? = nil,
        backendState: BackendState = .running,
        authURL: String? = nil,
        tailscaleIPs: [String] = [],
        magicDNSSuffix: String? = nil,
        currentTailnet: TailnetInfo? = nil,
        health: [String] = [],
        selfNode: PeerStatus? = nil,
        peers: [String: PeerStatus] = [:],
        users: [String: UserProfile] = [:]
    ) {
        self.version = version
        self.backendState = backendState
        self.authURL = authURL
        self.tailscaleIPs = tailscaleIPs
        self.magicDNSSuffix = magicDNSSuffix
        self.currentTailnet = currentTailnet
        self.health = health
        self.selfNode = selfNode
        self.peers = peers
        self.users = users
    }
}

extension PeerStatus {
    init(
        id: String? = nil,
        publicKey: String? = nil,
        hostName: String? = nil,
        dnsName: String? = nil,
        os: String? = nil,
        userID: Int64? = nil,
        tailscaleIPs: [String] = [],
        online: Bool = false,
        lastSeen: Date? = nil,
        exitNode: Bool = false,
        exitNodeOption: Bool = false,
        active: Bool = false,
        rxBytes: Int64 = 0,
        txBytes: Int64 = 0
    ) {
        self.id = id
        self.publicKey = publicKey
        self.hostName = hostName
        self.dnsName = dnsName
        self.os = os
        self.userID = userID
        self.tailscaleIPs = tailscaleIPs
        self.online = online
        self.lastSeen = lastSeen
        self.exitNode = exitNode
        self.exitNodeOption = exitNodeOption
        self.active = active
        self.rxBytes = rxBytes
        self.txBytes = txBytes
    }
}

extension TailnetInfo {
    init(name: String? = nil, magicDNSSuffix: String? = nil, magicDNSEnabled: Bool = true) {
        self.name = name
        self.magicDNSSuffix = magicDNSSuffix
        self.magicDNSEnabled = magicDNSEnabled
    }
}

extension UserProfile {
    init(id: Int64? = nil, loginName: String? = nil, displayName: String? = nil) {
        self.id = id
        self.loginName = loginName
        self.displayName = displayName
    }
}
