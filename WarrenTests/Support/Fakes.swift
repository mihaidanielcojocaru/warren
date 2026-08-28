//
//  Fakes.swift
//  WarrenTests
//

import Foundation
@testable import Warren

/// Records what would have been executed and replays a canned result. No test in
/// this target starts a process.
final class FakeProcessRunner: ProcessRunning, @unchecked Sendable {

    struct Invocation: Equatable {
        let executable: URL
        let arguments: [String]
        let timeout: TimeInterval
    }

    private let lock = NSLock()
    private var _invocations: [Invocation] = []
    private var _result: Result<ProcessResult, Error>
    /// Per-executable answers, for testing the fallback between binaries.
    private var _resultsByPath: [String: Result<ProcessResult, Error>] = [:]

    var invocations: [Invocation] {
        lock.lock(); defer { lock.unlock() }
        return _invocations
    }

    var lastInvocation: Invocation? { invocations.last }

    init(result: Result<ProcessResult, Error> = .success(.init(exitCode: 0, standardOutput: Data(), standardError: ""))) {
        self._result = result
    }

    convenience init(standardOutput: String, exitCode: Int32 = 0, standardError: String = "") {
        self.init(result: .success(ProcessResult(
            exitCode: exitCode,
            standardOutput: Data(standardOutput.utf8),
            standardError: standardError
        )))
    }

    convenience init(standardOutput: Data, exitCode: Int32 = 0, standardError: String = "") {
        self.init(result: .success(ProcessResult(
            exitCode: exitCode,
            standardOutput: standardOutput,
            standardError: standardError
        )))
    }

    /// Makes one specific executable answer differently from the rest.
    func setResult(_ result: Result<ProcessResult, Error>, forPath path: String) {
        lock.lock(); defer { lock.unlock() }
        _resultsByPath[path] = result
    }

    func setOutput(_ output: String, exitCode: Int32 = 0, forPath path: String) {
        setResult(.success(ProcessResult(exitCode: exitCode,
                                         standardOutput: Data(output.utf8),
                                         standardError: "")), forPath: path)
    }

    func setOutput(_ output: Data, exitCode: Int32 = 0, forPath path: String) {
        setResult(.success(ProcessResult(exitCode: exitCode,
                                         standardOutput: output,
                                         standardError: "")), forPath: path)
    }

    func run(_ executable: URL, arguments: [String], timeout: TimeInterval) throws -> ProcessResult {
        lock.lock()
        _invocations.append(Invocation(executable: executable, arguments: arguments, timeout: timeout))
        let result = _resultsByPath[executable.path] ?? _result
        lock.unlock()
        return try result.get()
    }
}

/// Stands in for the CLI when the thing under test is the store, not the parsing.
final class FakeTailscaleClient: TailscaleClienting, @unchecked Sendable {

    var statusResult: Result<TailscaleStatus, Error>
    var pingResult: Result<String, Error> = .success("pong")
    private(set) var exitNodeCalls: [String?] = []

    init(statusResult: Result<TailscaleStatus, Error> = .success(TailscaleStatus())) {
        self.statusResult = statusResult
    }

    func fetchStatus() throws -> TailscaleStatus { try statusResult.get() }

    func ping(host: String) throws -> String { try pingResult.get() }

    func setExitNode(address: String?) throws { exitNodeCalls.append(address) }

    private(set) var sentFiles: [(files: [URL], host: String)] = []

    func sendFiles(_ files: [URL], to host: String) throws {
        sentFiles.append((files, host))
    }
}

/// Stands in for the daemon's loopback API. No socket is ever opened.
final class FakeLocalAPI: LocalAPIRequesting, @unchecked Sendable {

    private let lock = NSLock()
    private var _result: Result<Data, Error>
    private var _requests: [LocalAPICredentials] = []

    var requests: [LocalAPICredentials] {
        lock.lock(); defer { lock.unlock() }
        return _requests
    }

    /// Answers consumed in order; the last one repeats.
    private var _queue: [Result<Data, Error>] = []

    init(result: Result<Data, Error> = .failure(LocalAPIError.unavailable("not configured"))) {
        self._result = result
    }

    convenience init(sequence: [Result<Data, Error>]) {
        self.init(result: sequence.last ?? .failure(LocalAPIError.unavailable("empty")))
        _queue = sequence
    }

    convenience init(json: Data) {
        self.init(result: .success(json))
    }

    func setResult(_ result: Result<Data, Error>) {
        lock.lock(); defer { lock.unlock() }
        _result = result
    }

    func statusJSON(using credentials: LocalAPICredentials, timeout: TimeInterval) throws -> Data {
        lock.lock()
        _requests.append(credentials)
        let result = _queue.isEmpty ? _result : _queue.removeFirst()
        lock.unlock()
        return try result.get()
    }
}
