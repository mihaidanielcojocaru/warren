//
//  MenuBarIcon.swift
//  Warren
//

import AppKit

/// The status item image: the burrow arch, whole when Tailscale is up and struck
/// through when it is not. Quiet by design — two states, and never a badge count.
///
/// Both assets are template images (pure black plus alpha), so AppKit tints them
/// for light mode, dark mode and the highlighted menu-open state. The artwork
/// lives in `icons/` as SVG; see `NOTES.md` for how it is rasterised.
enum MenuBarIcon {

    private enum Asset {
        static let connected = "WarrenTemplate"
        static let disconnected = "WarrenOfflineTemplate"
    }

    static func image(for state: TailnetState) -> NSImage {
        let isConnected = isConnected(state)
        let description = isConnected
            ? "\(AppInfo.name): connected to Tailscale"
            : "\(AppInfo.name): not connected to Tailscale"

        if let image = NSImage(named: isConnected ? Asset.connected : Asset.disconnected) {
            // The catalog already marks these as template images; setting it here
            // too costs nothing and keeps the behaviour explicit at the call site.
            image.isTemplate = true
            image.accessibilityDescription = description
            return image
        }
        return fallbackSymbol(isConnected: isConnected, description: description)
    }

    private static func isConnected(_ state: TailnetState) -> Bool {
        if case .ready = state { return true }
        return false
    }

    /// A status item with no image is an invisible app, which would leave no way
    /// to quit it. If the asset ever fails to load, fall back to a stock symbol.
    private static func fallbackSymbol(isConnected: Bool, description: String) -> NSImage {
        let configuration = NSImage.SymbolConfiguration(pointSize: 15, weight: .regular)
        let image = NSImage(systemSymbolName: isConnected ? "network" : "network.slash",
                            accessibilityDescription: description)
            ?? NSImage(systemSymbolName: "network", accessibilityDescription: description)
        let configured = image?.withSymbolConfiguration(configuration)
        configured?.isTemplate = true
        return configured ?? NSImage(size: NSSize(width: 18, height: 18))
    }
}
