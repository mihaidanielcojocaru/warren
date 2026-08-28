//
//  TailscaleClient.swift
//  Warren
//
//  Talking to the Tailscale CLI.
//

import Foundation

enum TailscaleClientError: LocalizedError, Equatable {
    case binaryNotFound
    case timedOut(TimeInterval)
    case commandFailed(exitCode: Int32, message: String)
    case unreadableOutput(String)
    case invalidTarget(String)

    var errorDescription: String? {
        switch self {
        case .binaryNotFound:
            return "The tailscale command line tool could not be found."
        case .timedOut(let seconds):
            return "Tailscale did not respond within \(Int(seconds)) seconds."
        case .commandFailed(_, let message):
            return message.isEmpty ? "The tailscale command failed." : message
        case .unreadableOutput(let detail):
            return "Tailscale returned something unreadable. \(detail)"
        case .invalidTarget(let target):
            return "\"\(target)\" is not a valid host name or address."
        }
    }
}

/// Where the CLI currently lives.
///
/// The client runs on a background queue while preferences change on the main
/// one, so the path cannot simply be read back off `Preferences` at call time —
/// that is a data race. This box is the hand-off point between the two.
final class TailscaleBinaryLocation: @unchecked Sendable {

    private let lock = NSLock()
    private var candidates: [URL]

    init(url: URL? = nil) {
        self.candidates = url.map { [$0] } ?? []
    }

    init(candidates: [URL]) {
        self.candidates = candidates
    }

    /// The binary to reach for first.
    var current: URL? {
        lock.lock()
        defer { lock.unlock() }
        return candidates.first
    }

    /// Everything worth trying, best first.
    var all: [URL] {
        lock.lock()
        defer { lock.unlock() }
        return candidates
    }

    func update(_ url: URL?) {
        update(candidates: url.map { [$0] } ?? [])
    }

    func update(candidates: [URL]) {
        lock.lock()
        defer { lock.unlock() }
        self.candidates = candidates
    }

    /// Move the binary that actually answered to the front, so the next poll does
    /// not pay for the broken one again.
    func promote(_ url: URL) {
        lock.lock()
        defer { lock.unlock() }
        guard candidates.first != url, let index = candidates.firstIndex(of: url) else { return }
        candidates.remove(at: index)
        candidates.insert(url, at: 0)
    }
}

/// Everything the app asks of Tailscale. A protocol so the store can be driven
/// by a fake in tests — no test in this project forks a process.
protocol TailscaleClienting: Sendable {

    /// Current tailnet status. Throws only when there is no readable payload at all.
    func fetchStatus() throws -> TailscaleStatus

    /// `tailscale ping`, returned as the text the CLI printed.
    func ping(host: String) throws -> String

    /// Routes traffic through `address`, or restores direct routing when `nil`.
    func setExitNode(address: String?) throws

    /// Sends files to a peer over Taildrop.
    func sendFiles(_ files: [URL], to host: String) throws
}

struct TailscaleClient: TailscaleClienting {

    /// Read on every call rather than captured once, so changing the path in
    /// preferences — or installing Tailscale while the app runs — takes effect
    /// without a relaunch.
    let location: TailscaleBinaryLocation
    let runner: ProcessRunning

    /// Polling goes over loopback; the CLI is a fallback and a way to learn the
    /// port and token once.
    let localAPI: LocalAPIRequesting
    let credentials: LocalAPICredentialStore

    var statusTimeout: TimeInterval = 5

    /// Ping needs longer than status: an unreachable peer is answered by the
    /// count running out, not by a fast failure.
    var pingTimeout: TimeInterval = 12

    /// `tailscale set` can bounce through an authorization prompt.
    var setTimeout: TimeInterval = 30

    /// Taildrop transfers are as slow as the files are large.
    var sendTimeout: TimeInterval = 900

    init(
        runner: ProcessRunning = ProcessRunner(),
        location: TailscaleBinaryLocation,
        localAPI: LocalAPIRequesting = TailscaleLocalAPI(),
        credentials: LocalAPICredentialStore = LocalAPICredentialStore()
    ) {
        self.runner = runner
        self.location = location
        self.localAPI = localAPI
        self.credentials = credentials
    }

    // MARK: - Status

    /// Prefers the daemon's loopback API and keeps the CLI as a fallback.
    ///
    /// The CLI is not a dependable poller on the standalone macOS build: it is the
    /// GUI app's own binary invoked with arguments, and when that handshake fails
    /// it prints "The Tailscale GUI failed to start" and **exits 0**. The local API
    /// is served by the daemon itself, so once the port and token are known —
    /// one CLI call per launch — polling never touches it again.
    func fetchStatus() throws -> TailscaleStatus {
        do {
            return try statusFromLocalAPI()
        } catch {
            return try statusFromCLI()
        }
    }

    private func statusFromLocalAPI() throws -> TailscaleStatus {
        if let cached = credentials.current {
            do {
                return try decodeStatus(localAPI.statusJSON(using: cached, timeout: statusTimeout))
            } catch {
                // A restarted daemon means a new port and token.
                credentials.invalidate()
            }
        }
        let fresh = try fetchCredentials()
        credentials.store(fresh)
        return try decodeStatus(localAPI.statusJSON(using: fresh, timeout: statusTimeout))
    }

    private func fetchCredentials() throws -> LocalAPICredentials {
        let (result, binary) = try execute(["debug", "local-creds"], timeout: statusTimeout)
        guard let credentials = LocalAPICredentials.parse(result.standardOutputText) else {
            throw TailscaleClientError.unreadableOutput(
                Self.unreadableDetail(binary: binary, result: result)
            )
        }
        return credentials
    }

    private func decodeStatus(_ data: Data) throws -> TailscaleStatus {
        try JSONDecoder().decode(TailscaleStatus.self, from: data)
    }

    /// Tries each candidate binary until one answers with JSON we can read.
    ///
    /// An exit code is not evidence of success here — see `fetchStatus` — so the
    /// parse decides, and whichever binary answered is promoted for next time.
    private func statusFromCLI() throws -> TailscaleStatus {
        let binaries = location.all
        guard !binaries.isEmpty else { throw TailscaleClientError.binaryNotFound }

        var firstFailure: TailscaleClientError?
        for binary in binaries {
            do {
                let result = try runner.run(binary, arguments: ["status", "--json"],
                                            timeout: statusTimeout)
                if let status = try? decodeStatus(result.standardOutput) {
                    location.promote(binary)
                    return status
                }
                firstFailure = firstFailure ?? (result.didSucceed
                    ? .unreadableOutput(Self.unreadableDetail(binary: binary, result: result))
                    : .commandFailed(exitCode: result.exitCode, message: Self.message(from: result)))
            } catch let error as ProcessRunnerError {
                firstFailure = firstFailure ?? Self.clientError(for: error)
            }
        }
        // Report the first binary's failure: it is the one the user expects to work.
        throw firstFailure ?? TailscaleClientError.binaryNotFound
    }

    // MARK: - Ping

    func ping(host: String) throws -> String {
        guard ConnectionTarget.isValidHost(host) else {
            throw TailscaleClientError.invalidTarget(host)
        }
        // `--c` really is spelled with two dashes and one letter.
        let (result, _) = try execute(["ping", "--c", "3", host], timeout: pingTimeout)
        let output = result.standardOutputText.trimmingCharacters(in: .whitespacesAndNewlines)

        if !result.didSucceed && output.isEmpty {
            throw TailscaleClientError.commandFailed(
                exitCode: result.exitCode,
                message: Self.message(from: result)
            )
        }
        // A failed ping still prints something worth showing ("no reply"), so the
        // text wins over the exit code here.
        return output.isEmpty ? "No response." : output
    }

    // MARK: - Exit node

    func setExitNode(address: String?) throws {
        let arguments: [String]
        if let address {
            guard ConnectionTarget.isValidHost(address) else {
                throw TailscaleClientError.invalidTarget(address)
            }
            arguments = ["set", "--exit-node", address]
        } else {
            // An empty value is how the CLI spells "stop using one".
            arguments = ["set", "--exit-node="]
        }

        let (result, _) = try execute(arguments, timeout: setTimeout)
        guard result.didSucceed else {
            throw TailscaleClientError.commandFailed(
                exitCode: result.exitCode,
                message: Self.message(from: result)
            )
        }
    }

    // MARK: - Taildrop

    /// `tailscale file cp <files...> <target>:` — the trailing colon is required.
    ///
    /// This is the friendliest transfer Warren can offer: it needs nothing set up
    /// on either machine, no file sharing, no sshd, no macFUSE.
    func sendFiles(_ files: [URL], to host: String) throws {
        guard ConnectionTarget.isValidHost(host) else {
            throw TailscaleClientError.invalidTarget(host)
        }
        guard !files.isEmpty else { return }

        let arguments = ["file", "cp"] + files.map(\.path) + ["\(host):"]
        let (result, _) = try execute(arguments, timeout: sendTimeout)
        guard result.didSucceed else {
            throw TailscaleClientError.commandFailed(
                exitCode: result.exitCode, message: Self.message(from: result)
            )
        }
    }

    // MARK: - Plumbing

    /// Returns the binary alongside the result, so failures can name what ran.
    private func execute(_ arguments: [String], timeout: TimeInterval) throws -> (ProcessResult, URL) {
        guard let executable = location.current else {
            throw TailscaleClientError.binaryNotFound
        }
        do {
            return (try runner.run(executable, arguments: arguments, timeout: timeout), executable)
        } catch let error as ProcessRunnerError {
            throw Self.clientError(for: error)
        }
    }

    private static func clientError(for error: ProcessRunnerError) -> TailscaleClientError {
        switch error {
        case .timedOut(let seconds): return .timedOut(seconds)
        case .launchFailed(let reason): return .commandFailed(exitCode: -1, message: reason)
        }
    }

    /// Says which binary was run and what it actually produced. "The JSON did not
    /// parse" on its own tells nobody anything; the path matters because the wrong
    /// binary is the likeliest cause, and the first line of output usually names it.
    private static func unreadableDetail(binary: URL, result: ProcessResult) -> String {
        guard !result.standardOutput.isEmpty else {
            return "\(binary.path) exited \(result.exitCode) without printing anything."
        }
        let head = String(data: result.standardOutput.prefix(200), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? "(not text)"
        return """
        \(binary.path) exited \(result.exitCode) and printed \
        \(result.standardOutput.count) bytes that are not JSON:

        \(head)
        """
    }

    /// Prefers stderr, falls back to stdout, and keeps it short enough for a menu.
    private static func message(from result: ProcessResult) -> String {
        let stderr = result.standardError.trimmingCharacters(in: .whitespacesAndNewlines)
        let text = stderr.isEmpty
            ? result.standardOutputText.trimmingCharacters(in: .whitespacesAndNewlines)
            : stderr
        return String(text.prefix(500))
    }
}
