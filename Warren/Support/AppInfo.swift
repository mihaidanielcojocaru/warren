//
//  AppInfo.swift
//  Warren
//

import Foundation

/// The app's own name, read from the bundle so menu text follows the product
/// rather than a hard-coded string.
enum AppInfo {
    static var name: String {
        let info = Bundle.main.infoDictionary
        return (info?["CFBundleDisplayName"] as? String)
            ?? (info?["CFBundleName"] as? String)
            ?? "Warren"
    }
}
