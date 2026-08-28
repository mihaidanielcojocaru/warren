//
//  PortProbe.swift
//  Warren
//
//  "Is anything listening?" — used to offer SMB only where it exists.
//

import Darwin
import Foundation

/// A single non-blocking TCP connect with a deadline.
///
/// Offering a Finder mount that cannot work is worse than not offering it, and
/// there is no way to ask Tailscale whether a peer serves SMB — so we knock.
enum PortProbe {

    static func isOpen(host: String, port: UInt16, timeout: TimeInterval = 1.2) -> Bool {
        guard ConnectionTarget.isValidHost(host) else { return false }

        var hints = addrinfo(ai_flags: 0, ai_family: AF_UNSPEC, ai_socktype: SOCK_STREAM,
                             ai_protocol: 0, ai_addrlen: 0, ai_canonname: nil,
                             ai_addr: nil, ai_next: nil)
        var info: UnsafeMutablePointer<addrinfo>?
        guard getaddrinfo(host, String(port), &hints, &info) == 0, let first = info else { return false }
        defer { freeaddrinfo(info) }

        for candidate in sequence(first: first, next: { $0.pointee.ai_next }) {
            if connects(to: candidate.pointee, timeout: timeout) { return true }
        }
        return false
    }

    private static func connects(to address: addrinfo, timeout: TimeInterval) -> Bool {
        let handle = socket(address.ai_family, address.ai_socktype, address.ai_protocol)
        guard handle >= 0 else { return false }
        defer { close(handle) }

        // Non-blocking, so the deadline is ours rather than the kernel's.
        let flags = fcntl(handle, F_GETFL, 0)
        guard flags >= 0, fcntl(handle, F_SETFL, flags | O_NONBLOCK) >= 0 else { return false }

        if connect(handle, address.ai_addr, address.ai_addrlen) == 0 { return true }
        guard errno == EINPROGRESS else { return false }

        var descriptor = pollfd(fd: handle, events: Int16(POLLOUT), revents: 0)
        guard poll(&descriptor, 1, Int32(timeout * 1000)) > 0 else { return false }

        // Connected, or refused? The socket error says which.
        var socketError: Int32 = 0
        var length = socklen_t(MemoryLayout<Int32>.size)
        guard getsockopt(handle, SOL_SOCKET, SO_ERROR, &socketError, &length) == 0 else { return false }
        return socketError == 0
    }
}
