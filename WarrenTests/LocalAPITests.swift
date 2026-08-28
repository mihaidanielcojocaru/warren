//
//  LocalAPITests.swift
//  WarrenTests
//

import XCTest
@testable import Warren

final class LocalAPITests: XCTestCase {

    private let binary = URL(fileURLWithPath: "/Applications/Tailscale.app/Contents/MacOS/tailscale")
    private let creds = "curl -u:vFOo9BAr1XyZ http://localhost:52481\n"

    // MARK: - Parsing `debug local-creds`

    func testParsesTheCurlLineTheCommandPrints() {
        let parsed = LocalAPICredentials.parse(creds)
        XCTAssertEqual(parsed, LocalAPICredentials(port: 52481, token: "vFOo9BAr1XyZ"))
    }

    /// It is a debug command with no compatibility promise, so accept the shapes
    /// it has been seen to take.
    func testParsesSpacingVariants() {
        XCTAssertEqual(LocalAPICredentials.parse("curl -u :tok http://localhost:1234")?.token, "tok")
        XCTAssertEqual(LocalAPICredentials.parse("curl -u:tok http://localhost:1234")?.port, 1234)
        XCTAssertEqual(LocalAPICredentials.parse("  curl -u:tok http://localhost:99  \n")?.port, 99)
    }

    func testRejectsAnythingUnrecognisable() {
        XCTAssertNil(LocalAPICredentials.parse(""))
        XCTAssertNil(LocalAPICredentials.parse("The Tailscale GUI failed to start"))
        XCTAssertNil(LocalAPICredentials.parse("curl http://localhost:1234"))
        XCTAssertNil(LocalAPICredentials.parse("curl -u:tok http://localhost:"))
    }

    // MARK: - Preferring the API

    private func makeClient(
        runner: FakeProcessRunner,
        api: FakeLocalAPI,
        store: LocalAPICredentialStore = LocalAPICredentialStore()
    ) -> TailscaleClient {
        TailscaleClient(runner: runner,
                        location: TailscaleBinaryLocation(url: binary),
                        localAPI: api,
                        credentials: store)
    }

    /// The whole point: once the port and token are known, polling never forks a
    /// process again — which is what made it unreliable.
    func testCachedCredentialsMeanNoProcessAtAll() throws {
        let runner = FakeProcessRunner(standardOutput: "should not be called")
        let api = FakeLocalAPI(json: try Fixture.data("status-sample"))
        let store = LocalAPICredentialStore()
        store.store(LocalAPICredentials(port: 1234, token: "tok"))

        let status = try makeClient(runner: runner, api: api, store: store).fetchStatus()

        XCTAssertEqual(status.peers.count, 5)
        XCTAssertTrue(runner.invocations.isEmpty, "the CLI should not have been touched")
        XCTAssertEqual(api.requests.first?.port, 1234)
    }

    func testCredentialsAreFetchedOnceThenReused() throws {
        let runner = FakeProcessRunner(standardOutput: creds)
        let api = FakeLocalAPI(json: try Fixture.data("status-sample"))
        let store = LocalAPICredentialStore()
        let client = makeClient(runner: runner, api: api, store: store)

        _ = try client.fetchStatus()
        _ = try client.fetchStatus()
        _ = try client.fetchStatus()

        XCTAssertEqual(runner.invocations.count, 1, "credentials should be fetched once")
        XCTAssertEqual(runner.invocations.first?.arguments, ["debug", "local-creds"])
        XCTAssertEqual(api.requests.count, 3)
        XCTAssertEqual(store.current?.port, 52481)
    }

    /// A restarted daemon means a new port and token; a 401 should send us back
    /// for fresh ones rather than failing.
    func testStaleCredentialsAreRefreshedAfterAnUnauthorized() throws {
        let runner = FakeProcessRunner(standardOutput: creds)
        let api = FakeLocalAPI(sequence: [
            .failure(LocalAPIError.unauthorized),
            .success(try Fixture.data("status-sample")),
        ])
        let store = LocalAPICredentialStore()
        store.store(LocalAPICredentials(port: 1, token: "stale"))

        let status = try makeClient(runner: runner, api: api, store: store).fetchStatus()

        XCTAssertEqual(status.peers.count, 5)
        XCTAssertEqual(api.requests.map(\.port), [1, 52481], "retried with fresh credentials")
        XCTAssertEqual(store.current?.port, 52481)
    }

    /// If the API cannot be reached at all, the CLI still gets its turn.
    func testFallsBackToTheCLIWhenTheAPIIsUnreachable() throws {
        let runner = FakeProcessRunner(standardOutput: try Fixture.data("status-sample"))
        let api = FakeLocalAPI(result: .failure(LocalAPIError.unavailable("refused")))

        let status = try makeClient(runner: runner, api: api).fetchStatus()

        XCTAssertEqual(status.peers.count, 5)
        XCTAssertTrue(runner.invocations.contains { $0.arguments == ["status", "--json"] })
    }

    // MARK: - Duplicate binaries

    /// macOS volumes are case-insensitive, so .../MacOS/tailscale and
    /// .../MacOS/Tailscale are one file. Trying both is not a fallback.
    func testCandidatesThatAreTheSameFileAreCollapsed() throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("warren-dedupe-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let original = directory.appendingPathComponent("tailscale")
        let hardLink = directory.appendingPathComponent("linked")
        try Data("#!/bin/sh\n".utf8).write(to: original)
        try FileManager.default.linkItem(at: original, to: hardLink)
        let separate = directory.appendingPathComponent("other")
        try Data("#!/bin/sh\n".utf8).write(to: separate)

        let collapsed = TailscaleBinaryLocator.deduplicated([original, hardLink, separate])

        XCTAssertEqual(collapsed, [original, separate])
    }
}
