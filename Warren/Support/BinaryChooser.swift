//
//  BinaryChooser.swift
//  Warren
//

import AppKit

@MainActor
enum BinaryChooser {

    /// Asks for the `tailscale` executable. `treatsFilePackagesAsDirectories` is
    /// on so the user can walk into Tailscale.app, which is where the real binary
    /// lives on most Macs.
    static func chooseTailscaleBinary(startingAt currentPath: String) -> String? {
        NSApp.activate(ignoringOtherApps: true)
        let panel = NSOpenPanel()
        panel.message = "Choose the tailscale command line tool"
        panel.prompt = "Choose"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.treatsFilePackagesAsDirectories = true
        panel.showsHiddenFiles = true
        panel.directoryURL = URL(fileURLWithPath: currentPath.isEmpty ? "/Applications" : currentPath)
            .deletingLastPathComponent()

        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        return url.path
    }
}
