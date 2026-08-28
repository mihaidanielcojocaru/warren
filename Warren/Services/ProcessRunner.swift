//
//  ProcessRunner.swift
//  Warren
//
//  Subprocess execution with a timeout, behind a protocol so tests never fork.
//

import Foundation

/// The result of a finished subprocess.
struct ProcessResult: Equatable {
    let exitCode: Int32
    let standardOutput: Data
    let standardError: String

    var standardOutputText: String {
        String(data: standardOutput, encoding: .utf8) ?? ""
    }

    var didSucceed: Bool { exitCode == 0 }
}

enum ProcessRunnerError: LocalizedError, Equatable {
    case launchFailed(String)
    case timedOut(TimeInterval)

    var errorDescription: String? {
        switch self {
        case .launchFailed(let reason): return "Could not start the process: \(reason)"
        case .timedOut(let seconds): return "The command did not finish within \(Int(seconds)) seconds."
        }
    }
}

/// Runs an executable with an argument vector. There is deliberately no variant
/// that takes a command *string*: nothing in this app builds a shell command out
/// of a device name.
protocol ProcessRunning: Sendable {
    func run(_ executable: URL, arguments: [String], timeout: TimeInterval) throws -> ProcessResult
}

extension ProcessRunning {
    func run(_ executable: URL, arguments: [String]) throws -> ProcessResult {
        try run(executable, arguments: arguments, timeout: 5)
    }
}

struct ProcessRunner: ProcessRunning {

    func run(_ executable: URL, arguments: [String], timeout: TimeInterval) throws -> ProcessResult {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.standardInput = FileHandle.nullDevice

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        // Drain both pipes on their own queues before waiting. A child that writes
        // more than the pipe buffer (64 KiB) blocks forever if we wait first — and
        // a large tailnet's status JSON goes well past that.
        var outputData = Data()
        var errorData = Data()
        let readers = DispatchGroup()
        DispatchQueue.global(qos: .userInitiated).async(group: readers) {
            outputData = outPipe.fileHandleForReading.readDataToEndOfFile()
        }
        DispatchQueue.global(qos: .userInitiated).async(group: readers) {
            errorData = errPipe.fileHandleForReading.readDataToEndOfFile()
        }

        let exited = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in exited.signal() }

        do {
            try process.run()
        } catch {
            throw ProcessRunnerError.launchFailed(error.localizedDescription)
        }

        if exited.wait(timeout: .now() + timeout) == .timedOut {
            terminate(process)
            readers.wait()
            throw ProcessRunnerError.timedOut(timeout)
        }

        // The pipes can still hold buffered bytes after exit; wait for EOF.
        readers.wait()

        return ProcessResult(
            exitCode: process.terminationStatus,
            standardOutput: outputData,
            standardError: String(data: errorData, encoding: .utf8) ?? ""
        )
    }

    /// Ask politely, then insist. Without the SIGKILL a wedged child would keep
    /// the reader queues (and the poll) alive indefinitely.
    private func terminate(_ process: Process) {
        process.terminate()
        let deadline = Date().addingTimeInterval(1)
        while process.isRunning && Date() < deadline {
            usleep(20_000)
        }
        if process.isRunning {
            kill(process.processIdentifier, SIGKILL)
        }
        process.waitUntilExit()
    }
}
