//
//  PreferencesTests.swift
//  WarrenTests
//

import XCTest
@testable import Warren

final class PreferencesTests: XCTestCase {

    private func makeDefaults() -> UserDefaults {
        UserDefaults(suiteName: "WarrenTests.\(UUID().uuidString)")!
    }

    // MARK: - Binary path

    func testAnEmptyPathFallsBackToTheKnownLocations() {
        let preferences = Preferences(defaults: makeDefaults())

        XCTAssertEqual(preferences.tailscaleBinaryPath, "")
        // Whatever is installed here, it must be one of the candidates.
        if let resolved = preferences.resolvedTailscaleURL() {
            XCTAssertTrue(TailscaleBinaryLocator.candidatePaths.contains(resolved.path))
        }
    }

    func testAStoredOverrideIsHonoured() {
        let defaults = makeDefaults()
        defaults.set("/bin/echo", forKey: "tailscaleBinaryPath")
        let preferences = Preferences(defaults: defaults)

        XCTAssertEqual(preferences.tailscaleBinaryPath, "/bin/echo")
        XCTAssertEqual(preferences.resolvedTailscaleURL()?.path, "/bin/echo")
    }

    /// An override that cannot be run resolves to nil rather than quietly falling
    /// back, so the menu can say the configured path is wrong.
    func testAnUnusableOverrideResolvesToNil() {
        let defaults = makeDefaults()
        defaults.set("/nonexistent/tailscale", forKey: "tailscaleBinaryPath")

        XCTAssertNil(Preferences(defaults: defaults).resolvedTailscaleURL())
    }

    func testADirectoryIsNotUsable() {
        XCTAssertFalse(TailscaleBinaryLocator.isUsable("/Applications"))
        XCTAssertFalse(TailscaleBinaryLocator.isUsable("/etc/hosts"))   // exists, not executable
        XCTAssertTrue(TailscaleBinaryLocator.isUsable("/bin/echo"))
    }

    func testChangingThePathPersists() {
        let defaults = makeDefaults()
        let preferences = Preferences(defaults: defaults)
        preferences.tailscaleBinaryPath = "/opt/homebrew/bin/tailscale"

        XCTAssertEqual(Preferences(defaults: defaults).tailscaleBinaryPath, "/opt/homebrew/bin/tailscale")
    }

    // MARK: - User names

    func testDefaultUserNameFallsBackToTheLoginName() {
        XCTAssertEqual(Preferences(defaults: makeDefaults()).defaultUsername, NSUserName())
    }

    func testPerDeviceOverrideWinsOverTheDefault() throws {
        let preferences = Preferences(defaults: makeDefaults())
        preferences.defaultUsername = "mihai"
        let device = try XCTUnwrap(
            TailnetSnapshot(status: try Fixture.sampleStatus()).peers.first { $0.displayName == "nas" }
        )

        XCTAssertEqual(preferences.username(for: device), "mihai")
        preferences.setUsernameOverride("root", forDNSName: try XCTUnwrap(device.dnsName))
        XCTAssertEqual(preferences.username(for: device), "root")
    }

    func testClearingAnOverrideRestoresTheDefault() throws {
        let preferences = Preferences(defaults: makeDefaults())
        preferences.defaultUsername = "mihai"
        let device = try XCTUnwrap(
            TailnetSnapshot(status: try Fixture.sampleStatus()).peers.first { $0.displayName == "nas" }
        )
        let dnsName = try XCTUnwrap(device.dnsName)

        preferences.setUsernameOverride("root", forDNSName: dnsName)
        preferences.setUsernameOverride("   ", forDNSName: dnsName)

        XCTAssertNil(preferences.usernameOverrides[dnsName])
        XCTAssertEqual(preferences.username(for: device), "mihai")
    }

    func testPollIntervalIsClampedToTheAllowedRange() {
        let preferences = Preferences(defaults: makeDefaults())

        XCTAssertEqual(preferences.pollInterval, 10)
        preferences.pollInterval = 900
        XCTAssertEqual(preferences.pollInterval, 60)
        preferences.pollInterval = 0.5
        XCTAssertEqual(preferences.pollInterval, 5)
    }
}
