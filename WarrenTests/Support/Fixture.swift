//
//  Fixture.swift
//  WarrenTests
//

import Foundation
import XCTest
@testable import Warren

/// Loads checked-in sample payloads. Nothing in this test target shells out — the
/// fixtures are the only source of tailnet data.
enum Fixture {

    static func data(
        _ name: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> Data {
        let bundle = Bundle(for: FixtureToken.self)
        // Depending on how the resource is copied, the fixture lands either at the
        // bundle root or under its folder; look in both rather than caring.
        let url = bundle.url(forResource: name, withExtension: "json")
            ?? bundle.url(forResource: name, withExtension: "json", subdirectory: "Fixtures")
        guard let url else {
            XCTFail("Missing fixture \(name).json in the test bundle", file: file, line: line)
            throw CocoaError(.fileNoSuchFile)
        }
        return try Data(contentsOf: url)
    }

    /// The full sample tailnet: an online Linux peer, an offline peer, an active
    /// exit node, a peer with an empty `DNSName`, a peer that is not an object at
    /// all, a peer whose fields have the wrong types, and an unknown top-level key.
    static func sampleStatus(file: StaticString = #filePath, line: UInt = #line) throws -> TailscaleStatus {
        try decode(TailscaleStatus.self, from: data("status-sample", file: file, line: line))
    }

    static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        try JSONDecoder().decode(type, from: data)
    }

    /// Decodes a literal payload, for the one-off shapes a fixture should not carry.
    static func decode<T: Decodable>(_ type: T.Type, json: String) throws -> T {
        try decode(type, from: Data(json.utf8))
    }
}

private final class FixtureToken {}
