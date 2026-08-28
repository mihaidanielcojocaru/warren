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
}

struct TailscaleClient: TailscaleClienting {

    /// Read on every call rather than captured once, so changing the path in
    /// preferences — or installing Tailscale while the app runs — takes effect
    /// without a relaunch.
    let location: TailscaleBinaryLocation
    let runner: ProcessRunning

    var statusTimeout: TimeInterval = 5

    /// Ping needs longer than status: an unreachable peer is answered by the
    /// count running out, not by a fast failure.
    var pingTimeout: TimeInterval = 12

    /// `tailscale set` can bounce through an authorization prompt.
    var setTimeout: TimeInterval = 30

    init(runner: ProcessRunning = ProcessRunner(), location: TailscaleBinaryLocation) {
        self.runner = runner
        self.location = location
    }

    // MARK: - Status

    /// Tries each candidate binary until one answers with JSON we can read.
    ///
    /// Falling back matters because a broken CLI does not announce itself: the
    /// `tailscale` inside Tailscale.app brokers through the GUI app, and when that
    /// handshake fails it prints "The Tailscale GUI failed to start" on stdout and
    /// **exits 0**. An exit code is not evidence of success, so the parse is what
    /// decides, and the binary that answered is promoted for next time.
    func fetchStatus() throws -> TailscaleStatus {
        let binaries = location.all
        guard !binaries.isEmpty else { throw TailscaleClientError.binaryNotFound }

        var firstFailure: TailscaleClientError?
        for binary in binaries {
            do {
                let result = try runner.run(binary, arguments: ["status", "--json"],
                                            timeout: statusTimeout)
                if let status = try? JSONDecoder().decode(TailscaleStatus.self,
                                                          from: result.standardOutput) {
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
