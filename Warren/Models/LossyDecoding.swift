//
//  LossyDecoding.swift
//  Warren
//
//  Decoding helpers for JSON we do not own.
//

import Foundation

/// `tailscale status --json` is an internal CLI surface with no compatibility
/// promise: keys appear and disappear between releases, and several are emitted
/// as `null` rather than omitted (1.102.3 does this for `Addrs`, `ExtraRecords`
/// and `ClientVersion`). Every helper below degrades to a default instead of
/// throwing, so an unknown key or a changed type can never empty the menu.
extension KeyedDecodingContainer {

    /// A missing key, an explicit `null`, or a value of the wrong type all
    /// collapse to `nil`.
    func lossy<T: Decodable>(_ type: T.Type = T.self, _ key: Key) -> T? {
        guard let value = try? decodeIfPresent(T.self, forKey: key) else { return nil }
        return value
    }

    /// As `lossy(_:_:)`, but `null` and wrong types collapse to an empty array.
    func lossyArray<T: Decodable>(_ type: T.Type = T.self, _ key: Key) -> [T] {
        lossy([T].self, key) ?? []
    }

    func lossyBool(_ key: Key, default fallback: Bool = false) -> Bool {
        lossy(Bool.self, key) ?? fallback
    }

    func lossyInt64(_ key: Key, default fallback: Int64 = 0) -> Int64 {
        lossy(Int64.self, key) ?? fallback
    }

    /// Decodes a JSON object into a dictionary, dropping only the entries that
    /// fail to decode. One malformed peer must not cost us the other nine.
    func lossyDictionary<T: Decodable>(_ type: T.Type = T.self, _ key: Key) -> [String: T] {
        guard let raw = lossy([String: LossyValue<T>].self, key) else { return [:] }
        return raw.compactMapValues(\.value)
    }

    /// A timestamp in the format Go's `time.RFC3339Nano` produces.
    func lossyDate(_ key: Key) -> Date? {
        guard let string = lossy(String.self, key) else { return nil }
        return RFC3339.date(from: string)
    }

    /// A trimmed, non-empty string. Tailscale writes `""` where another API
    /// would write `null` — an unregistered node has an empty `DNSName`.
    func lossyNonEmptyString(_ key: Key) -> String? {
        guard let value = lossy(String.self, key)?
            .trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
        return value
    }
}

/// Turns a per-element decoding failure into `nil` instead of failing the whole
/// container. See `lossyDictionary(_:_:)`.
struct LossyValue<Value: Decodable>: Decodable {
    let value: Value?

    init(from decoder: Decoder) throws {
        value = try? Value(from: decoder)
    }
}

/// Parsing for the timestamp format the Go standard library emits.
enum RFC3339 {

    /// Go renders a zero `time.Time` as year one, and Tailscale uses that to
    /// mean "never": a peer that has never been seen, a key that never expires.
    private static let goZeroYearPrefix = "0001-"

    // `ISO8601DateFormatter` cannot do this job. With `.withFractionalSeconds`
    // it rejects "2026-08-28T10:40:00Z"; without it, it rejects
    // "2026-08-28T10:40:00.1Z" — and Tailscale emits both, because
    // `time.RFC3339Nano` trims trailing zeros from the fraction. `ISO8601FormatStyle`
    // accepts every variant (verified against 0-9 fractional digits, and against
    // both `Z` and `+02:00` offsets); the second style is kept only as a
    // belt-and-braces fallback for a format we have not seen yet.
    private static let primary = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
    private static let fallback = Date.ISO8601FormatStyle(includingFractionalSeconds: false)

    /// Returns `nil` for an empty string, for Go's zero time, and for anything
    /// unparseable — all of which mean "no useful timestamp" to the caller.
    static func date(from string: String) -> Date? {
        guard !string.isEmpty, !string.hasPrefix(goZeroYearPrefix) else { return nil }
        if let date = try? primary.parse(string) { return date }
        return try? fallback.parse(string)
    }
}
