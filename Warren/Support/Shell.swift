//
//  Shell.swift
//  Warren
//
//  Quoting and validation for values that reach a shell or AppleScript.
//

import Foundation

/// Hostnames, usernames and addresses in this app arrive over the network, from
/// a tailnet that may include machines other people named. Everything that ends
/// up in a command line is validated here first and quoted second.
///
/// Process invocations pass argument arrays and never need any of this. It exists
/// for the two places a string is unavoidable: `Terminal.app`'s and iTerm2's
/// AppleScript `do script`, which takes a shell command line.
enum Shell {

    /// Wraps a value in single quotes for POSIX `sh`, ending and re-opening the
    /// quoting around any embedded single quote. Inside single quotes no shell
    /// metacharacter has meaning, so this is total.
    static func quote(_ argument: String) -> String {
        "'" + argument.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    /// Builds a `sh` command line from an argument vector, quoting every element.
    static func commandLine(_ arguments: [String]) -> String {
        arguments.map(quote).joined(separator: " ")
    }
}

/// Escaping for values interpolated into an AppleScript source string.
enum AppleScriptLiteral {

    /// Renders a Swift string as an AppleScript double-quoted literal.
    static func quote(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"" + escaped + "\""
    }
}

/// Input validation for the two untrusted values that reach a command line.
///
/// This is belt and braces: callers quote as well. But rejecting a hostname that
/// cannot possibly be a hostname is cheaper than trusting quoting alone, and it
/// turns a malformed peer into a disabled menu item rather than a strange
/// command.
enum ConnectionTarget {

    /// A DNS name, an IPv4 literal, or an IPv6 literal. Deliberately strict:
    /// letters, digits, dot, hyphen, colon, and percent for a zone id.
    static func isValidHost(_ host: String) -> Bool {
        guard !host.isEmpty, host.count <= 253, !host.hasPrefix("-") else { return false }
        return host.unicodeScalars.allSatisfy { scalar in
            CharacterSet.alphanumerics.contains(scalar)
                || scalar == "." || scalar == "-" || scalar == ":" || scalar == "%" || scalar == "_"
        }
    }

    /// A POSIX-ish login name. Rejects anything that could be read as a flag,
    /// an option, or a second argument.
    static func isValidUsername(_ username: String) -> Bool {
        guard !username.isEmpty, username.count <= 32, !username.hasPrefix("-") else { return false }
        return username.unicodeScalars.allSatisfy { scalar in
            CharacterSet.alphanumerics.contains(scalar)
                || scalar == "." || scalar == "-" || scalar == "_" || scalar == "$"
        }
    }
}
