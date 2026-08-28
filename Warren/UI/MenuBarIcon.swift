//
//  MenuBarIcon.swift
//  Warren
//

import AppKit

/// The status item image. Quiet by design: one symbol, two weights of presence,
/// and never a badge count.
enum MenuBarIcon {

    private static let pointSize: CGFloat = 15

    static func image(for state: TailnetState) -> NSImage {
        isConnected(state) ? connected() : disconnected()
    }

    private static func isConnected(_ state: TailnetState) -> Bool {
        if case .ready = state { return true }
        return false
    }

    private static func connected() -> NSImage {
        symbol(named: "network") ?? NSImage()
    }

    /// Prefers the slashed symbol; if this system's SF Symbols set does not have
    /// it, dims the plain one instead. Both readings are legible in a menu bar.
    private static func disconnected() -> NSImage {
        if let slashed = symbol(named: "network.slash") { return slashed }
        guard let base = symbol(named: "network") else { return NSImage() }
        return dimmed(base)
    }

    private static func symbol(named name: String) -> NSImage? {
        let configuration = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .regular)
        let image = NSImage(systemSymbolName: name, accessibilityDescription: AppInfo.name)?
            .withSymbolConfiguration(configuration)
        image?.isTemplate = true
        return image
    }

    private static func dimmed(_ image: NSImage) -> NSImage {
        let faded = NSImage(size: image.size, flipped: false) { rect in
            image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 0.45)
            return true
        }
        faded.isTemplate = true
        return faded
    }
}
