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

    func run(_ executable: URL, arguments: [String], timeout: TimeInterval) throws -> ProcessResult {
        lock.lock()
        _invocations.append(Invocation(executable: executable, arguments: arguments, timeout: timeout))
        let result = _result
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
}
