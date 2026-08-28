//
//  TailscaleStatusDecodingTests.swift
//  WarrenTests
//
//  The wire format is not ours and is not stable. These tests pin the one
//  guarantee we make about it: a surprising payload degrades, it never throws.
//

import XCTest
@testable import Warren

final class TailscaleStatusDecodingTests: XCTestCase {

    // MARK: - Sample tailnet

    func testDecodesTopLevelStatus() throws {
        let status = try Fixture.sampleStatus()

        XCTAssertEqual(status.backendState, .running)
        XCTAssertEqual(status.version, "1.102.3-t9329c3677-ga522f65e9")
        XCTAssertEqual(status.magicDNSSuffix, "tailnet-example.ts.net")
        XCTAssertEqual(status.currentTailnet?.name, "example.com")
        XCTAssertEqual(status.currentTailnet?.magicDNSEnabled, true)
        XCTAssertEqual(status.tailscaleIPs, ["100.64.0.1", "fd7a:115c:a1e0::1"])
        XCTAssertTrue(status.health.isEmpty)
        XCTAssertEqual(status.users.count, 2)
        XCTAssertEqual(status.users["1002"]?.loginName, "colleague@example.com")
        // `AuthURL` is "" in the payload, which means "not waiting on a login".
        XCTAssertNil(status.authURL)
    }

    func testDecodesSelfNode() throws {
        let selfNode = try XCTUnwrap(Fixture.sampleStatus().selfNode)

        XCTAssertEqual(selfNode.hostName, "mac-mini")
        XCTAssertEqual(selfNode.dnsName, "mac-mini.tailnet-example.ts.net.")
        XCTAssertEqual(selfNode.os, "macOS")
        XCTAssertTrue(selfNode.online)
        XCTAssertEqual(selfNode.rxBytes, 1_048_576)
    }

    /// The fixture carries an `UnexpectedFutureKey` object at the top level and an
    /// `UnknownPeerField` inside a peer. Both must simply be ignored.
    func testUnknownKeysAreIgnored() throws {
        let status = try Fixture.sampleStatus()

        XCTAssertNotNil(status.selfNode)
        XCTAssertEqual(status.peers.count, 5)
    }

    /// One `Peer` value is a string rather than an object. It is dropped; the
    /// other five decode normally.
    func testMalformedPeerIsDroppedButSiblingsSurvive() throws {
        let status = try Fixture.sampleStatus()
        let hostNames = Set(status.peers.values.compactMap(\.hostName))

        XCTAssertEqual(status.peers.count, 5)
        XCTAssertEqual(hostNames, ["nas", "old-laptop", "exit-fra", "spare-iphone", "flaky-router"])
    }

    /// A peer whose fields have the wrong types keeps the fields that are valid
    /// and falls back on the rest — it is not dropped, because a peer you can
    /// still see the name of is more useful than a peer that vanished.
    func testPeerWithWrongFieldTypesFallsBackToDefaults() throws {
        let router = try XCTUnwrap(try peer(named: "flaky-router"))

        XCTAssertFalse(router.online)                 // "yes"
        XCTAssertTrue(router.tailscaleIPs.isEmpty)    // a bare string, not an array
        XCTAssertEqual(router.rxBytes, 0)             // "lots"
        XCTAssertNil(router.userID)                   // "1001" as a string
        XCTAssertNil(router.lastSeen)                 // "not a timestamp"
        XCTAssertFalse(router.exitNode)               // 0
        XCTAssertTrue(router.exitNodeOption)          // a valid bool, kept
        XCTAssertEqual(router.dnsName, "flaky-router.tailnet-example.ts.net.")
    }

    func testEmptyDNSNameDecodesAsNil() throws {
        let phone = try XCTUnwrap(try peer(named: "spare-iphone"))

        XCTAssertNil(phone.dnsName)
        XCTAssertEqual(phone.hostName, "spare-iphone")
    }

    // MARK: - Timestamps

    /// Go's `time.RFC3339Nano` trims trailing zeros from the fraction, so the same
    /// payload mixes zero, one and nine fractional digits.
    func testTimestampsWithAnyNumberOfFractionalDigits() throws {
        let status = try Fixture.sampleStatus()

        assertDate(try peerIn(status, "nas")?.lastSeen,
                   equals: utc(2026, 8, 28, 10, 40, 0))
        assertDate(try peerIn(status, "old-laptop")?.lastSeen,
                   equals: utc(2026, 8, 28, 7, 12, 33, fraction: 0.1))
        assertDate(try peerIn(status, "exit-fra")?.lastSeen,
                   equals: utc(2026, 8, 28, 10, 41, 2, fraction: 0.123456789))
        assertDate(status.selfNode?.lastSeen,
                   equals: utc(2026, 8, 28, 10, 42, 11, fraction: 0.5))
    }

    /// Tailscale writes Go's zero time for "never seen". That is not a date in
    /// the year 1, it is the absence of one.
    func testGoZeroTimestampIsNil() throws {
        XCTAssertNil(try peer(named: "spare-iphone")?.lastSeen)
        XCTAssertNil(RFC3339.date(from: "0001-01-01T00:00:00Z"))
    }

    func testTimestampParsingHandlesOffsetsAndRejectsJunk() {
        assertDate(RFC3339.date(from: "2026-08-28T12:40:00+02:00"), equals: utc(2026, 8, 28, 10, 40, 0))
        assertDate(RFC3339.date(from: "2026-08-28T12:40:00.55+02:00"), equals: utc(2026, 8, 28, 10, 40, 0, fraction: 0.55))
        XCTAssertNil(RFC3339.date(from: ""))
        XCTAssertNil(RFC3339.date(from: "yesterday"))
        XCTAssertNil(RFC3339.date(from: "2026-08-28"))
    }

    // MARK: - Backend state

    func testKnownBackendStatesDecode() throws {
        let expected: [String: BackendState] = [
            "NoState": .noState,
            "NeedsMachineAuth": .needsMachineAuth,
            "NeedsLogin": .needsLogin,
            "Stopped": .stopped,
            "Starting": .starting,
            "Running": .running,
            "InUseOtherUser": .inUseOtherUser,
        ]
        for (wire, state) in expected {
            let status = try Fixture.decode(TailscaleStatus.self, json: #"{"BackendState": "\#(wire)"}"#)
            XCTAssertEqual(status.backendState, state, "decoding \(wire)")
            XCTAssertEqual(state.wireValue, wire)
        }
    }

    /// A state added by a future release has to survive as text so it can be
    /// reported, rather than being quietly rounded to "running".
    func testUnknownBackendStateIsCarriedThrough() throws {
        let status = try Fixture.decode(TailscaleStatus.self, json: #"{"BackendState": "Teleporting"}"#)

        XCTAssertEqual(status.backendState, .unrecognized("Teleporting"))
        XCTAssertEqual(status.backendState.wireValue, "Teleporting")
    }

    // MARK: - Degenerate payloads

    func testEmptyObjectDecodes() throws {
        let status = try Fixture.decode(TailscaleStatus.self, json: "{}")

        XCTAssertEqual(status.backendState, .unrecognized(""))
        XCTAssertNil(status.selfNode)
        XCTAssertNil(status.magicDNSSuffix)
        XCTAssertTrue(status.peers.isEmpty)
        XCTAssertTrue(status.users.isEmpty)
        XCTAssertTrue(status.tailscaleIPs.isEmpty)
    }

    /// 1.102.3 emits `null` for `Addrs`, `ExtraRecords` and `ClientVersion`; assume
    /// any collection can arrive that way.
    func testNullCollectionsDecodeAsEmpty() throws {
        let json = #"{"BackendState": "Running", "Peer": null, "User": null, "TailscaleIPs": null, "Health": null, "Self": null, "CurrentTailnet": null}"#
        let status = try Fixture.decode(TailscaleStatus.self, json: json)

        XCTAssertEqual(status.backendState, .running)
        XCTAssertTrue(status.peers.isEmpty)
        XCTAssertTrue(status.users.isEmpty)
        XCTAssertTrue(status.tailscaleIPs.isEmpty)
        XCTAssertTrue(status.health.isEmpty)
        XCTAssertNil(status.selfNode)
        XCTAssertNil(status.currentTailnet)
    }

    func testWrongTypeForEveryTopLevelFieldStillDecodes() throws {
        let json = #"{"BackendState": 42, "Peer": "nope", "TailscaleIPs": {"a": 1}, "MagicDNSSuffix": [], "Self": 7}"#
        let status = try Fixture.decode(TailscaleStatus.self, json: json)

        XCTAssertEqual(status.backendState, .unrecognized(""))
        XCTAssertTrue(status.peers.isEmpty)
        XCTAssertTrue(status.tailscaleIPs.isEmpty)
        XCTAssertNil(status.magicDNSSuffix)
        XCTAssertNil(status.selfNode)
    }

    /// Only a payload that is not a JSON object at all is allowed to throw; the
    /// client turns that into the "can't reach the daemon" menu state.
    func testNonObjectPayloadThrows() {
        XCTAssertThrowsError(try Fixture.decode(TailscaleStatus.self, json: "[]"))
        XCTAssertThrowsError(try Fixture.decode(TailscaleStatus.self, json: "not json"))
    }

    // MARK: - Helpers

    private func peer(named hostName: String) throws -> PeerStatus? {
        try peerIn(Fixture.sampleStatus(), hostName)
    }

    private func peerIn(_ status: TailscaleStatus, _ hostName: String) throws -> PeerStatus? {
        status.peers.values.first { $0.hostName == hostName }
    }

    private func utc(
        _ year: Int, _ month: Int, _ day: Int,
        _ hour: Int, _ minute: Int, _ second: Int,
        fraction: TimeInterval = 0
    ) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let components = DateComponents(
            year: year, month: month, day: day, hour: hour, minute: minute, second: second
        )
        return calendar.date(from: components)!.addingTimeInterval(fraction)
    }

    private func assertDate(
        _ actual: Date?,
        equals expected: Date,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard let actual else {
            return XCTFail("expected \(expected), got nil", file: file, line: line)
        }
        XCTAssertEqual(
            actual.timeIntervalSince1970, expected.timeIntervalSince1970,
            accuracy: 0.001, file: file, line: line
        )
    }
}
