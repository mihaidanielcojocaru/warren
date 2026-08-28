//
//  TailnetSnapshot.swift
//  Warren
//
//  One poll's worth of tailnet, plus the states the menu can be in.
//

import Foundation

/// The result of one successful poll, already sorted and partitioned the way the
/// menu presents it. Deriving this once keeps the view layer free of policy.
struct TailnetSnapshot: Equatable {

    let backendState: BackendState

    /// Human-readable tailnet name, e.g. `example.com`.
    let tailnetName: String?

    /// e.g. `tailnet-example.ts.net`.
    let magicDNSSuffix: String?

    /// This machine. `nil` before the backend has a node key.
    let selfDevice: Device?

    /// Every other node, sorted by display name.
    let peers: [Device]

    let capturedAt: Date

    var onlinePeers: [Device] { peers.filter(\.isOnline) }

    var offlinePeers: [Device] { peers.filter { !$0.isOnline } }

    /// The peer currently carrying this machine's traffic, if any.
    var activeExitNode: Device? { peers.first(where: \.isExitNode) }

    /// Peers that can be turned on as an exit node.
    var exitNodeCandidates: [Device] { peers.filter(\.offersExitNode) }

    init(status: TailscaleStatus, capturedAt: Date = Date()) {
        // `CurrentTailnet.MagicDNSSuffix` and the top-level one agree in practice;
        // prefer the tailnet's own copy and fall back, since either may be absent.
        let suffix = status.currentTailnet?.magicDNSSuffix ?? status.magicDNSSuffix

        self.backendState = status.backendState
        self.tailnetName = status.currentTailnet?.name
        self.magicDNSSuffix = suffix
        self.capturedAt = capturedAt
        self.selfDevice = status.selfNode.map {
            Device(peer: $0, nodeKey: "self", magicDNSSuffix: suffix, isSelf: true)
        }
        self.peers = status.peers
            .map { Device(peer: $0.value, nodeKey: $0.key, magicDNSSuffix: suffix, isSelf: false) }
            .sorted(by: TailnetSnapshot.isOrderedBefore)
    }

    /// Alphabetical by display name, case- and numeral-aware (`mac-2` before
    /// `mac-10`), with the node id as a tie-break so that two machines sharing a
    /// name cannot swap places between polls.
    private static func isOrderedBefore(_ lhs: Device, _ rhs: Device) -> Bool {
        switch lhs.displayName.localizedStandardCompare(rhs.displayName) {
        case .orderedAscending: return true
        case .orderedDescending: return false
        case .orderedSame: return lhs.id < rhs.id
        }
    }
}

/// Everything the menu can be showing. Each failure is a distinct, quiet state
/// with something actionable behind it — never an empty list, never an alert.
enum TailnetState: Equatable {

    /// First poll has not finished yet.
    case loading

    /// Backend is running. Note that `snapshot.peers` may still be empty, which
    /// the menu shows as "No other devices in this tailnet".
    case ready(TailnetSnapshot)

    /// No `tailscale` binary at any known path or at the configured override.
    case binaryNotFound

    /// Backend is up but unauthenticated.
    case needsLogin

    /// Backend is up and logged in, but switched off.
    case disconnected

    /// Backend is coming up; the next poll will likely succeed.
    case starting

    /// The CLI failed, timed out, or returned something we could not read.
    case unreachable(TailnetFailure)

    /// Maps a decoded snapshot onto the state the menu should show.
    init(snapshot: TailnetSnapshot) {
        switch snapshot.backendState {
        case .running:
            self = .ready(snapshot)
        case .needsLogin, .needsMachineAuth:
            self = .needsLogin
        case .stopped:
            self = .disconnected
        case .starting, .noState:
            self = .starting
        case .inUseOtherUser:
            self = .unreachable(TailnetFailure(
                summary: "Tailscale is in use by another user",
                detail: "Another user account on this Mac is signed in to Tailscale."
            ))
        case .unrecognized(let value):
            self = .unreachable(TailnetFailure(
                summary: "Tailscale is in an unknown state",
                detail: value.isEmpty ? "The daemon reported no state." : "The daemon reported \"\(value)\"."
            ))
        }
    }
}

/// A failure phrased for a menu item rather than for a log.
struct TailnetFailure: Equatable {

    /// The menu item's title. Plain language, no error codes.
    let summary: String

    /// stderr, or a decoding error — shown in a submenu for the curious.
    let detail: String?
}
