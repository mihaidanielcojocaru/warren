//
//  RelativeTime.swift
//  Warren
//

import Foundation

/// "3 hours ago" for the offline list.
enum RelativeTime {

    private static let formatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        formatter.dateTimeStyle = .named
        return formatter
    }()

    /// `nil` means the node has never been seen, which is not the same as "a long
    /// time ago" and should not be rendered as a date.
    static func lastSeen(_ date: Date?, relativeTo now: Date = Date()) -> String {
        guard let date else { return "Never seen" }
        return formatter.localizedString(for: date, relativeTo: now)
    }
}
