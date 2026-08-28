//
//  DeviceOS+Symbol.swift
//  Warren
//
//  Presentation for DeviceOS, kept out of the model.
//

import Foundation

extension DeviceOS {

    /// SF Symbols has no Linux or BSD glyph, so those borrow the closest honest
    /// stand-in rather than a penguin that does not exist.
    var symbolName: String {
        switch self {
        case .macOS: return "laptopcomputer"
        case .iOS: return "iphone"
        case .tvOS: return "appletv"
        case .linux: return "terminal"
        case .windows: return "pc"
        case .android: return "candybarphone"
        case .freeBSD, .openBSD: return "server.rack"
        case .unknown: return "desktopcomputer"
        }
    }
}
