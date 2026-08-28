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
    private var url: URL?

    init(url: URL? = nil) {
        self.url = url
    }

    var current: URL? {
        lock.lock()
        defer { lock.unlock() }
        return url
    }

    func update(_ url: URL?) {
        lock.lock()
        defer { lock.unlock() }
        self.url = url
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

    func fetchStatus() throws -> TailscaleStatus {
        let result = try execute(["status", "--json"], timeout: statusTimeout)

        // Decode stdout whatever the exit code says. A backend that is stopped or
        // logged out still prints a complete payload with the state in it, and
        // whether the CLI also exits non-zero for those cases is an implementation
        // detail we would rather not depend on. Only a payload we cannot read at
        // all becomes an error.
        if let status = try? JSONDecoder().decode(TailscaleStatus.self, from: result.standardOutput) {
            return status
        }

        if !result.didSucceed {
            throw TailscaleClientError.commandFailed(
                exitCode: result.exitCode,
                message: Self.message(from: result)
            )
        }
        throw TailscaleClientError.unreadableOutput(
            result.standardOutput.isEmpty ? "It printed nothing." : "The JSON did not parse."
        )
    }

    // MARK: - Ping

    func ping(host: String) throws -> String {
        guard ConnectionTarget.isValidHost(host) else {
            throw TailscaleClientError.invalidTarget(host)
        }
        // `--c` really is spelled with two dashes and one letter.
        let result = try execute(["ping", "--c", "3", host], timeout: pingTimeout)
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

        let result = try execute(arguments, timeout: setTimeout)
        guard result.didSucceed else {
            throw TailscaleClientError.commandFailed(
                exitCode: result.exitCode,
                message: Self.message(from: result)
            )
        }
    }

    // MARK: - Plumbing

    private func execute(_ arguments: [String], timeout: TimeInterval) throws -> ProcessResult {
        guard let executable = location.current else {
            throw TailscaleClientError.binaryNotFound
        }
        do {
            return try runner.run(executable, arguments: arguments, timeout: timeout)
        } catch let error as ProcessRunnerError {
            switch error {
            case .timedOut(let seconds):
                throw TailscaleClientError.timedOut(seconds)
            case .launchFailed(let reason):
                throw TailscaleClientError.commandFailed(exitCode: -1, message: reason)
            }
        }
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
