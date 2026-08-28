//
//  FilePicker.swift
//  Warren
//

import AppKit

@MainActor
enum FilePicker {

    /// Files to send. Directories are excluded because Taildrop takes files.
    static func chooseFiles(prompt: String) -> [URL]? {
        NSApp.activate(ignoringOtherApps: true)
        let panel = NSOpenPanel()
        panel.message = prompt
        panel.prompt = "Send"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true

        guard panel.runModal() == .OK else { return nil }
        return panel.urls
    }
}
