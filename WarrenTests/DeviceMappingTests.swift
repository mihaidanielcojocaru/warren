//
//  DeviceMappingTests.swift
//  WarrenTests
//
//  Wire model -> what the menu actually renders and connects to.
//

import XCTest
@testable import Warren

final class DeviceMappingTests: XCTestCase {

    private let suffix = "tailnet-example.ts.net"

    // MARK: - Names

    /// The name the machine calls itself wins: MagicDNS only ever holds a
    /// lower-cased, hyphenated derivative of it.
    func testDisplayNamePrefersHostNameOverTheMagicDNSLabel() {
        XCTAssertEqual(
            Device.displayName(
                dnsName: "mihais-macbook-air.tailnet-example.ts.net",
                hostName: "Mihai's MacBook Air",
                magicDNSSuffix: suffix,
                fallbackAddress: nil
            ),
            "Mihai's MacBook Air"
        )
    }

    func testDisplayNameStripsMagicDNSSuffixAndTrailingDot() {
        XCTAssertEqual(
            Device.displayName(
                dnsName: "nas.tailnet-example.ts.net",
                hostName: nil,
                magicDNSSuffix: suffix,
                fallbackAddress: nil
            ),
            "nas"
        )
    }

    /// A device shared in from another tailnet carries a suffix that is not ours;
    /// the first label is still the right short name.
    func testDisplayNameUsesFirstLabelForAForeignSuffix() {
        XCTAssertEqual(
            Device.displayName(
                dnsName: "printer.other-tailnet.ts.net",
                hostName: nil,
                magicDNSSuffix: suffix,
                fallbackAddress: nil
            ),
            "printer"
        )
    }

    /// HostName, then the MagicDNS label, then an address, then a placeholder —
    /// the menu always needs something to render.
    func testDisplayNameFallsBackThroughDNSLabelToAddress() {
        XCTAssertEqual(
            Device.displayName(dnsName: nil, hostName: "spare-iphone",
                               magicDNSSuffix: suffix, fallbackAddress: "100.64.0.5"),
            "spare-iphone"
        )
        XCTAssertEqual(
            Device.displayName(dnsName: "nas.\(suffix)", hostName: nil,
                               magicDNSSuffix: suffix, fallbackAddress: "100.64.0.5"),
            "nas"
        )
        XCTAssertEqual(
            Device.displayName(dnsName: nil, hostName: nil,
                               magicDNSSuffix: suffix, fallbackAddress: "100.64.0.5"),
            "100.64.0.5"
        )
        XCTAssertEqual(
            Device.displayName(dnsName: nil, hostName: nil,
                               magicDNSSuffix: suffix, fallbackAddress: nil),
            "Unnamed device"
        )
    }

    /// Names with spaces and punctuation reach a mount path and an sshfs option,
    /// so they have to survive the round trip intact.
    func testDisplayNameKeepsSpacesAndPunctuation() {
        XCTAssertEqual(
            Device.displayName(dnsName: "s22-al-utilizatorului-maria.\(suffix)",
                               hostName: "S22 al utilizatorului Maria",
                               magicDNSSuffix: suffix, fallbackAddress: nil),
            "S22 al utilizatorului Maria"
        )
    }

    func testTrailingDotStripping() {
        XCTAssertEqual(Device.strippingTrailingDot("nas.tailnet-example.ts.net."), "nas.tailnet-example.ts.net")
        XCTAssertEqual(Device.strippingTrailingDot("nas.tailnet-example.ts.net"), "nas.tailnet-example.ts.net")
        XCTAssertNil(Device.strippingTrailingDot(""))
        XCTAssertNil(Device.strippingTrailingDot("   "))
        XCTAssertNil(Device.strippingTrailingDot("."))
        XCTAssertNil(Device.strippingTrailingDot(nil))
    }

    // MARK: - Addresses

    func testConnectionHostPrefersDNSNameWithoutTrailingDot() throws {
        let device = try device(named: "nas")

        XCTAssertEqual(device.dnsName, "nas.tailnet-example.ts.net")
        XCTAssertEqual(device.connectionHost, "nas.tailnet-example.ts.net")
    }

    func testConnectionHostFallsBackToIPv4WhenDNSNameIsEmpty() throws {
        let device = try device(named: "spare-iphone")

        XCTAssertNil(device.dnsName)
        XCTAssertEqual(device.ipv4, "100.64.0.5")
        XCTAssertEqual(device.connectionHost, "100.64.0.5")
    }

    func testAddressesAreSplitByFamily() throws {
        let device = try device(named: "nas")

        XCTAssertEqual(device.ipv4, "100.64.0.2")
        XCTAssertEqual(device.ipv6, "fd7a:115c:a1e0::2")
    }

    /// The wrong-typed peer has neither addresses nor a usable name shape, but it
    /// does have a DNS name, so it stays connectable.
    func testConnectionHostSurvivesAnUnusableAddressList() throws {
        let device = try device(named: "flaky-router")

        XCTAssertNil(device.ipv4)
        XCTAssertNil(device.ipv6)
        XCTAssertEqual(device.connectionHost, "flaky-router.tailnet-example.ts.net")
    }

    func testConnectionHostIsNilWithNeitherNameNorAddress() {
        let device = Device(peer: PeerStatus(hostName: "ghost"), nodeKey: "k", magicDNSSuffix: suffix, isSelf: false)

        XCTAssertNil(device.connectionHost)
        XCTAssertEqual(device.displayName, "ghost")
    }

    // MARK: - Identity

    func testIdentityPrefersStableNodeIDThenKey() {
        let withID = Device(peer: PeerStatus(id: "n1", publicKey: "pk"), nodeKey: "map-key", magicDNSSuffix: nil, isSelf: false)
        let withKey = Device(peer: PeerStatus(publicKey: "pk"), nodeKey: "map-key", magicDNSSuffix: nil, isSelf: false)
        let bare = Device(peer: PeerStatus(), nodeKey: "map-key", magicDNSSuffix: nil, isSelf: false)

        XCTAssertEqual(withID.id, "n1")
        XCTAssertEqual(withKey.id, "pk")
        XCTAssertEqual(bare.id, "map-key")
    }

    func testOperatingSystemMapping() {
        XCTAssertEqual(DeviceOS(wireValue: "linux"), .linux)
        XCTAssertEqual(DeviceOS(wireValue: "macOS"), .macOS)
        XCTAssertEqual(DeviceOS(wireValue: "MACOS"), .macOS)
        XCTAssertEqual(DeviceOS(wireValue: "iOS"), .iOS)
        XCTAssertEqual(DeviceOS(wireValue: "android"), .android)
        XCTAssertEqual(DeviceOS(wireValue: "windows"), .windows)
        XCTAssertEqual(DeviceOS(wireValue: "plan9"), .unknown("plan9"))
        XCTAssertEqual(DeviceOS(wireValue: nil), .unknown(""))
        XCTAssertEqual(DeviceOS(wireValue: "plan9").displayName, "plan9")
        XCTAssertEqual(DeviceOS(wireValue: nil).displayName, "Unknown")
    }

    // MARK: - Taildrop availability

    /// Tailscale reports 1 for "can take a file now"; anything else is a reason
    /// it cannot. Trusting its verdict beats guessing from `online`.
    func testTaildropAvailabilityFollowsTailscalesVerdict() {
        XCTAssertTrue(Device.canReceiveFiles(peer: PeerStatus(online: true, taildropTarget: 1)))
        XCTAssertFalse(Device.canReceiveFiles(peer: PeerStatus(online: false, taildropTarget: 5)))
        // Online, but Tailscale says no — believe Tailscale.
        XCTAssertFalse(Device.canReceiveFiles(peer: PeerStatus(online: true, taildropTarget: 7)))
    }

    /// Older daemons omit the field; fall back to the dominant reason.
    func testTaildropFallsBackToOnlineWhenTheFieldIsMissing() {
        XCTAssertTrue(Device.canReceiveFiles(peer: PeerStatus(online: true)))
        XCTAssertFalse(Device.canReceiveFiles(peer: PeerStatus(online: false)))
    }

    // MARK: - Snapshot

    func testSnapshotSeparatesSelfFromPeers() throws {
        let snapshot = try sampleSnapshot()

        XCTAssertEqual(snapshot.selfDevice?.displayName, "mac-mini")
        XCTAssertEqual(snapshot.selfDevice?.isSelf, true)
        XCTAssertEqual(snapshot.peers.count, 5)
        XCTAssertFalse(snapshot.peers.contains { $0.displayName == "mac-mini" })
        XCTAssertFalse(snapshot.peers.contains(where: \.isSelf))
        XCTAssertEqual(snapshot.tailnetName, "example.com")
        XCTAssertEqual(snapshot.magicDNSSuffix, suffix)
    }

    func testSnapshotPartitionsOnlineAndOffline() throws {
        let snapshot = try sampleSnapshot()

        XCTAssertEqual(snapshot.onlinePeers.map(\.displayName), ["exit-fra", "nas", "spare-iphone"])
        XCTAssertEqual(snapshot.offlinePeers.map(\.displayName), ["flaky-router", "old-laptop"])
    }

    func testSnapshotFindsTheActiveExitNodeAndItsCandidates() throws {
        let snapshot = try sampleSnapshot()

        XCTAssertEqual(snapshot.activeExitNode?.displayName, "exit-fra")
        // `flaky-router` advertises the option too, even though it is offline.
        XCTAssertEqual(snapshot.exitNodeCandidates.map(\.displayName), ["exit-fra", "flaky-router"])
    }

    func testSnapshotSortsCaseInsensitivelyAndNumerically() {
        let status = TailscaleStatus(
            magicDNSSuffix: suffix,
            peers: [
                "k1": PeerStatus(id: "1", dnsName: "mac-10.\(suffix)."),
                "k2": PeerStatus(id: "2", dnsName: "mac-2.\(suffix)."),
                "k3": PeerStatus(id: "3", dnsName: "Zeta.\(suffix)."),
                "k4": PeerStatus(id: "4", dnsName: "alpha.\(suffix)."),
            ]
        )

        XCTAssertEqual(
            TailnetSnapshot(status: status).peers.map(\.displayName),
            ["alpha", "mac-2", "mac-10", "Zeta"]
        )
    }

    /// Two machines really can report the same name. Ordering has to stay put
    /// between polls, or rows move under the cursor.
    func testSnapshotOrderingIsStableForDuplicateNames() {
        let status = TailscaleStatus(
            magicDNSSuffix: suffix,
            peers: [
                "k1": PeerStatus(id: "node-b", hostName: "iphone"),
                "k2": PeerStatus(id: "node-a", hostName: "iphone"),
            ]
        )

        XCTAssertEqual(TailnetSnapshot(status: status).peers.map(\.id), ["node-a", "node-b"])
    }

    // MARK: - Menu state

    func testStateMapsEachBackendState() {
        XCTAssertEqual(state(for: .needsLogin), .needsLogin)
        XCTAssertEqual(state(for: .needsMachineAuth), .needsLogin)
        XCTAssertEqual(state(for: .stopped), .disconnected)
        XCTAssertEqual(state(for: .starting), .starting)
        XCTAssertEqual(state(for: .noState), .starting)

        guard case .ready = state(for: .running) else {
            return XCTFail("Running should map to .ready")
        }
        guard case .unreachable(let failure) = state(for: .unrecognized("Teleporting")) else {
            return XCTFail("an unknown state should map to .unreachable")
        }
        XCTAssertEqual(failure.summary, "Tailscale is in an unknown state")
        XCTAssertEqual(failure.detail, "The daemon reported \"Teleporting\".")
    }

    /// An empty tailnet is a normal, successful poll — the menu says so itself.
    func testRunningWithNoPeersIsStillReady() {
        guard case .ready(let snapshot) = state(for: .running) else {
            return XCTFail("expected .ready")
        }
        XCTAssertTrue(snapshot.peers.isEmpty)
    }

    // MARK: - Helpers

    private func sampleSnapshot() throws -> TailnetSnapshot {
        TailnetSnapshot(status: try Fixture.sampleStatus())
    }

    private func device(named displayName: String) throws -> Device {
        let snapshot = try sampleSnapshot()
        return try XCTUnwrap(
            snapshot.peers.first { $0.displayName == displayName },
            "no peer named \(displayName)"
        )
    }

    private func state(for backendState: BackendState) -> TailnetState {
        TailnetState(snapshot: TailnetSnapshot(status: TailscaleStatus(backendState: backendState)))
    }
}
