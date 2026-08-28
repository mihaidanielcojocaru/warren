//
//  MenuBarIconTests.swift
//  WarrenTests
//

import AppKit
import XCTest
@testable import Warren

final class MenuBarIconTests: XCTestCase {

    private func connectedState() throws -> TailnetState {
        TailnetState(snapshot: TailnetSnapshot(status: try Fixture.sampleStatus()))
    }

    func testBothAssetsLoadFromTheCatalog() {
        XCTAssertNotNil(NSImage(named: "WarrenTemplate"), "missing WarrenTemplate imageset")
        XCTAssertNotNil(NSImage(named: "WarrenOfflineTemplate"), "missing WarrenOfflineTemplate imageset")
    }

    /// The whole point of the two assets: the icon has to actually change.
    func testConnectedAndDisconnectedUseDifferentArtwork() throws {
        let connected = MenuBarIcon.image(for: try connectedState())
        let disconnected = MenuBarIcon.image(for: .binaryNotFound)

        XCTAssertNotEqual(connected.name(), disconnected.name())
        XCTAssertNotEqual(connected.tiffRepresentation, disconnected.tiffRepresentation)
    }

    /// Only `.ready` is "connected"; everything else, including the very first
    /// render before any poll has finished, shows the struck-through arch.
    func testEveryNonReadyStateShowsTheDisconnectedIcon() throws {
        let disconnectedName = MenuBarIcon.image(for: .binaryNotFound).name()
        let states: [TailnetState] = [
            .loading, .binaryNotFound, .needsLogin, .disconnected, .starting,
            .unreachable(TailnetFailure(summary: "nope", detail: nil)),
        ]
        for state in states {
            XCTAssertEqual(MenuBarIcon.image(for: state).name(), disconnectedName, "\(state)")
        }
        XCTAssertNotEqual(MenuBarIcon.image(for: try connectedState()).name(), disconnectedName)
    }

    /// Template images are what let AppKit tint for light, dark and highlighted.
    func testIconsAreTemplateImages() throws {
        XCTAssertTrue(MenuBarIcon.image(for: try connectedState()).isTemplate)
        XCTAssertTrue(MenuBarIcon.image(for: .disconnected).isTemplate)
    }

    func testIconsCarryAnAccessibilityDescription() throws {
        XCTAssertNotNil(MenuBarIcon.image(for: try connectedState()).accessibilityDescription)
        XCTAssertNotNil(MenuBarIcon.image(for: .disconnected).accessibilityDescription)
    }
}
