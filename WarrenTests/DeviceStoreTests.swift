//
//  DeviceStoreTests.swift
//  WarrenTests
//

import Combine
import XCTest
@testable import Warren

@MainActor
final class DeviceStoreTests: XCTestCase {

    private var cancellables = Set<AnyCancellable>()

    private func makePreferences() -> Preferences {
        // A throwaway suite, so tests never touch the real settings.
        let defaults = UserDefaults(suiteName: "WarrenTests.\(UUID().uuidString)")!
        return Preferences(defaults: defaults)
    }

    private func makeStore(_ client: FakeTailscaleClient) -> DeviceStore {
        DeviceStore(client: client, preferences: makePreferences())
    }

    /// `refresh()` hands off to a background queue, so wait for it to land.
    private func refreshAndWait(_ store: DeviceStore, file: StaticString = #filePath, line: UInt = #line) {
        let settled = expectation(description: "refresh finished")
        store.$isRefreshing
            .dropFirst()
            .filter { $0 == false }
            .first()
            .sink { _ in settled.fulfill() }
            .store(in: &cancellables)
        store.refresh()
        wait(for: [settled], timeout: 2)
    }

    // MARK: - State

    func testSuccessfulPollBecomesReady() throws {
        let store = makeStore(FakeTailscaleClient(statusResult: .success(try Fixture.sampleStatus())))
        refreshAndWait(store)

        guard case .ready(let snapshot) = store.state else {
            return XCTFail("expected .ready, got \(store.state)")
        }
        XCTAssertEqual(snapshot.peers.count, 5)
        XCTAssertEqual(store.onlinePeers.count, 3)
        XCTAssertEqual(store.offlinePeers.count, 2)
    }

    func testMissingBinaryBecomesItsOwnState() {
        let client = FakeTailscaleClient(statusResult: .failure(TailscaleClientError.binaryNotFound))
        let store = makeStore(client)
        refreshAndWait(store)

        XCTAssertEqual(store.state, .binaryNotFound)
    }

    func testDaemonFailuresKeepTheirDetailForTheSubmenu() {
        let client = FakeTailscaleClient(statusResult: .failure(
            TailscaleClientError.commandFailed(exitCode: 1, message: "failed to connect to local tailscaled")
        ))
        let store = makeStore(client)
        refreshAndWait(store)

        guard case .unreachable(let failure) = store.state else {
            return XCTFail("expected .unreachable, got \(store.state)")
        }
        XCTAssertEqual(failure.summary, "Can't reach the Tailscale daemon")
        XCTAssertEqual(failure.detail, "failed to connect to local tailscaled")
    }

    func testTimeoutIsAlsoUnreachable() {
        let store = makeStore(FakeTailscaleClient(statusResult: .failure(TailscaleClientError.timedOut(5))))
        refreshAndWait(store)

        guard case .unreachable = store.state else {
            return XCTFail("expected .unreachable, got \(store.state)")
        }
    }

    func testLoggedOutBackendBecomesNeedsLogin() {
        let status = TailscaleStatus(backendState: .needsLogin)
        let store = makeStore(FakeTailscaleClient(statusResult: .success(status)))
        refreshAndWait(store)

        XCTAssertEqual(store.state, .needsLogin)
    }

    // MARK: - Search

    func testSearchFiltersOnShortNameAndDNSName() throws {
        let store = makeStore(FakeTailscaleClient(statusResult: .success(try Fixture.sampleStatus())))
        refreshAndWait(store)

        store.searchText = "nas"
        XCTAssertEqual(store.onlinePeers.map(\.displayName), ["nas"])

        store.searchText = "EXIT-FRA"          // case-insensitive
        XCTAssertEqual(store.onlinePeers.map(\.displayName), ["exit-fra"])

        store.searchText = "tailnet-example"   // matches the full DNS name
        XCTAssertEqual(store.onlinePeers.count, 2)

        store.searchText = "nothing here"
        XCTAssertTrue(store.onlinePeers.isEmpty)
        XCTAssertTrue(store.offlinePeers.isEmpty)
    }

    /// The field earns its place only past a dozen peers.
    func testSearchFieldAppearsOnlyForLargeTailnets() throws {
        let small = makeStore(FakeTailscaleClient(statusResult: .success(try Fixture.sampleStatus())))
        refreshAndWait(small)
        XCTAssertFalse(small.shouldShowSearchField)

        let peers = Dictionary(uniqueKeysWithValues: (1...13).map { index in
            ("key-\(index)", PeerStatus(id: "n\(index)", hostName: "node-\(index)"))
        })
        let large = makeStore(FakeTailscaleClient(statusResult: .success(TailscaleStatus(peers: peers))))
        refreshAndWait(large)
        XCTAssertTrue(large.shouldShowSearchField)
    }

    func testClosingTheMenuClearsTheSearch() throws {
        let store = makeStore(FakeTailscaleClient(statusResult: .success(try Fixture.sampleStatus())))
        refreshAndWait(store)

        store.searchText = "nas"
        store.menuClosed()
        XCTAssertTrue(store.searchText.isEmpty)
    }
}
