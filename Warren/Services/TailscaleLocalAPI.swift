//
//  TailscaleLocalAPI.swift
//  Warren
//
//  Talking to the daemon over loopback instead of forking the CLI.
//

import Foundation

/// Port and bearer token for the daemon's local HTTP API.
struct LocalAPICredentials: Equatable {
    let port: Int
    let token: String

    /// Parses the output of `tailscale debug local-creds`, which is a ready-made
    /// curl invocation rather than anything structured:
    ///
    ///     curl -u:vFOo9BAr1 http://localhost:52481
    ///
    /// Deliberately forgiving about the shape — this is a debug command, not an
    /// interface with a compatibility promise.
    static func parse(_ output: String) -> LocalAPICredentials? {
        guard let portRange = output.range(of: #"localhost:[0-9]+"#, options: .regularExpression),
              let port = Int(output[portRange].dropFirst("localhost:".count)),
              let tokenRange = output.range(of: #"-u\s*:?[^\s]+"#, options: .regularExpression)
        else { return nil }

        let token = output[tokenRange]
            .drop { $0 == "-" || $0 == "u" }
            .drop { $0 == " " || $0 == ":" }
        guard !token.isEmpty else { return nil }
        return LocalAPICredentials(port: port, token: String(token))
    }
}

enum LocalAPIError: LocalizedError, Equatable {
    case unauthorized
    case unavailable(String)
    case badStatus(Int)

    var errorDescription: String? {
        switch self {
        case .unauthorized: return "The local API rejected the token."
        case .unavailable(let reason): return "The local API could not be reached. \(reason)"
        case .badStatus(let code): return "The local API returned HTTP \(code)."
        }
    }
}

/// A `GET` against the daemon's local API. Behind a protocol so tests never open
/// a socket.
protocol LocalAPIRequesting: Sendable {
    func statusJSON(using credentials: LocalAPICredentials, timeout: TimeInterval) throws -> Data
}

struct TailscaleLocalAPI: LocalAPIRequesting {

    private let session: URLSession

    init(session: URLSession? = nil) {
        // Ephemeral, and explicitly proxy-free: this is loopback, and a configured
        // HTTP proxy has no business intercepting it.
        let configuration = URLSessionConfiguration.ephemeral
        configuration.connectionProxyDictionary = [:]
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        self.session = session ?? URLSession(configuration: configuration)
    }

    func statusJSON(using credentials: LocalAPICredentials, timeout: TimeInterval) throws -> Data {
        guard let url = URL(string: "http://127.0.0.1:\(credentials.port)/localapi/v0/status") else {
            throw LocalAPIError.unavailable("The port is not usable.")
        }
        var request = URLRequest(url: url, timeoutInterval: timeout)
        // Empty user name, token as the password — see `tailscale debug local-creds`.
        let encoded = Data(":\(credentials.token)".utf8).base64EncodedString()
        request.setValue("Basic \(encoded)", forHTTPHeaderField: "Authorization")
        // tailscaled expects to be addressed as its unix socket. Recent builds no
        // longer require it, but sending it costs nothing and older ones do.
        request.setValue("local-tailscaled.sock", forHTTPHeaderField: "Host")

        var result: Result<Data, Error>?
        let finished = DispatchSemaphore(value: 0)
        session.dataTask(with: request) { data, response, error in
            defer { finished.signal() }
            if let error {
                result = .failure(LocalAPIError.unavailable(error.localizedDescription))
                return
            }
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            switch code {
            case 200: result = .success(data ?? Data())
            case 401, 403: result = .failure(LocalAPIError.unauthorized)
            default: result = .failure(LocalAPIError.badStatus(code))
            }
        }.resume()

        guard finished.wait(timeout: .now() + timeout + 1) == .success else {
            throw LocalAPIError.unavailable("It did not respond in time.")
        }
        return try (result ?? .failure(LocalAPIError.unavailable("No response."))).get()
    }
}

/// Caches the credentials so the CLI is spawned once rather than every poll.
final class LocalAPICredentialStore: @unchecked Sendable {

    private let lock = NSLock()
    private var cached: LocalAPICredentials?

    var current: LocalAPICredentials? {
        lock.lock()
        defer { lock.unlock() }
        return cached
    }

    func store(_ credentials: LocalAPICredentials?) {
        lock.lock()
        defer { lock.unlock() }
        cached = credentials
    }

    func invalidate() {
        store(nil)
    }
}
