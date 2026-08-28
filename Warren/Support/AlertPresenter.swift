//
//  AlertPresenter.swift
//  Warren
//
//  NSAlert plumbing. An agent with no Dock icon has to ask for the foreground
//  before it puts a window on screen, or the alert opens behind everything.
//

import AppKit

@MainActor
enum AlertPresenter {

    /// Returns true when the user chose the first (default) button.
    @discardableResult
    static func show(
        title: String,
        message: String? = nil,
        style: NSAlert.Style = .warning,
        buttons: [String] = ["OK"]
    ) -> Bool {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.alertStyle = style
        alert.messageText = title
        if let message { alert.informativeText = message }
        for button in buttons { alert.addButton(withTitle: button) }
        return alert.runModal() == .alertFirstButtonReturn
    }

    /// A notice with nothing to decide. Returns Void so it can be used as the
    /// body of an early-returning `guard`.
    static func notify(title: String, message: String? = nil) {
        _ = show(title: title, message: message)
    }

    /// Shows an error with its recovery suggestion, when it has one.
    static func show(error: Error) {
        let title = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        let suggestion = (error as? LocalizedError)?.recoverySuggestion
        show(title: title, message: suggestion)
    }

    /// A one-line text prompt, for "SSH as…".
    static func promptForText(
        title: String,
        message: String? = nil,
        defaultValue: String = "",
        confirmTitle: String = "Connect"
    ) -> String? {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = title
        if let message { alert.informativeText = message }
        alert.addButton(withTitle: confirmTitle)
        alert.addButton(withTitle: "Cancel")

        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
        field.stringValue = defaultValue
        field.placeholderString = "Username"
        alert.accessoryView = field
        alert.window.initialFirstResponder = field

        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        let value = field.stringValue.trimmingCharacters(in: .whitespaces)
        return value.isEmpty ? nil : value
    }
}
