//
//  ShellTests.swift
//  WarrenTests
//
//  The AppleScript path is the only place a device name becomes a command
//  string, so its quoting is worth pinning down.
//

import XCTest
@testable import Warren

final class ShellTests: XCTestCase {

    func testQuotingWrapsInSingleQuotes() {
        XCTAssertEqual(Shell.quote("nas"), "'nas'")
        XCTAssertEqual(Shell.quote("nas.tailnet-example.ts.net"), "'nas.tailnet-example.ts.net'")
    }

    /// The classic escape: close the quote, emit a literal quote, reopen.
    func testQuotingNeutralisesEmbeddedSingleQuotes() {
        XCTAssertEqual(Shell.quote("it's"), #"'it'\''s'"#)
    }

    func testQuotingNeutralisesShellMetacharacters() {
        let hostile = "nas; rm -rf ~"
        XCTAssertEqual(Shell.quote(hostile), "'nas; rm -rf ~'")

        for metacharacter in ["$(id)", "`id`", "&& curl x", "| tee", "> /tmp/x", "\n"] {
            let quoted = Shell.quote(metacharacter)
            XCTAssertTrue(quoted.hasPrefix("'") && quoted.hasSuffix("'"), quoted)
        }
    }

    func testCommandLineQuotesEveryElement() {
        XCTAssertEqual(
            Shell.commandLine(["ssh", "root@nas; rm -rf ~"]),
            "'ssh' 'root@nas; rm -rf ~'"
        )
    }

    func testAppleScriptLiteralEscapesQuotesAndBackslashes() {
        XCTAssertEqual(AppleScriptLiteral.quote(#"say "hi""#), #""say \"hi\"""#)
        XCTAssertEqual(AppleScriptLiteral.quote(#"back\slash"#), #""back\\slash""#)
    }

    // MARK: - Validation

    func testValidHostsAreAccepted() {
        for host in ["nas", "nas.tailnet-example.ts.net", "100.64.0.2", "fd7a:115c:a1e0::2", "web-01"] {
            XCTAssertTrue(ConnectionTarget.isValidHost(host), host)
        }
    }

    func testHostileHostsAreRejected() {
        for host in ["", "nas; rm -rf ~", "$(id)", "`id`", "nas && curl x", "nas evil",
                     "-oProxyCommand=x", "nas\nx", "nas|x", "nas>x", String(repeating: "a", count: 254)] {
            XCTAssertFalse(ConnectionTarget.isValidHost(host), host)
        }
    }

    func testUsernameValidation() {
        for name in ["root", "mihai", "deploy-bot", "user_1", "ci.runner"] {
            XCTAssertTrue(ConnectionTarget.isValidUsername(name), name)
        }
        for name in ["", "-oProxyCommand=x", "a b", "root;id", "root@host", String(repeating: "a", count: 33)] {
            XCTAssertFalse(ConnectionTarget.isValidUsername(name), name)
        }
    }
}
