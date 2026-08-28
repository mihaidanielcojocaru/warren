//
//  TerminalLauncher.swift
//  Warren
//
//  Opening a command in the user's terminal of choice.
//

import AppKit
import Foundation

enum TerminalLauncherError: LocalizedError {
    case noTerminalInstalled
    case notInstalled(TerminalApp)
    case automationDenied(TerminalApp)
    case launchFailed(TerminalApp, String)

    var errorDescription: String? {
        switch self {
        case .noTerminalInstalled:
            return "No supported terminal application was found."
        case .notInstalled(let app):
            return "\(app.displayName) is not installed."
        case .automationDenied(let app):
            return "Warren is not allowed to control \(app.displayName)."
        case .launchFailed(let app, let reason):
            return "\(app.displayName) could not be started. \(reason)"
        }
    }

    /// The two failures worth telling the user how to fix.
    var recoverySuggestion: String? {
        switch self {
        case .automationDenied:
            return "Open System Settings › Privacy & Security › Automation and turn on the switch for Warren."
        case .noTerminalInstalled:
            return "Install one of Ghostty, iTerm2, WezTerm, Kitty, Alacritty, or use the built-in Terminal."
        default:
            return nil
        }
    }
}

protocol TerminalLaunching {
    /// Runs an argument vector in a new terminal window.
    func launch(command: [String], using app: TerminalApp) async throws

    /// Which of the supported terminals are actually present.
    func installedTerminals() -> [TerminalApp]
}

extension TerminalLaunching {
    /// The configured terminal when it is installed, else the first one that is.
    func resolveTerminal(configured: TerminalApp?) throws -> TerminalApp {
        let installed = installedTerminals()
        if let configured {
            guard installed.contains(configured) else { throw TerminalLauncherError.notInstalled(configured) }
            return configured
        }
        guard let first = installed.first else { throw TerminalLauncherError.noTerminalInstalled }
        return first
    }
}

struct TerminalLauncher: TerminalLaunching {

    private let workspace = NSWorkspace.shared

    func installedTerminals() -> [TerminalApp] {
        TerminalApp.allCases.filter { bundleURL(for: $0) != nil }
    }

    func launch(command: [String], using app: TerminalApp) async throws {
        guard bundleURL(for: app) != nil else { throw TerminalLauncherError.notInstalled(app) }

        if app.usesAppleScript {
            try runAppleScript(command: command, in: app)
        } else {
            try await launchWithArguments(command: command, in: app)
        }
    }

    private func bundleURL(for app: TerminalApp) -> URL? {
        workspace.urlForApplication(withBundleIdentifier: app.bundleIdentifier)
    }

    // MARK: - AppleScript terminals

    /// Terminal.app and iTerm2 are told to run a *shell command line*, so this is
    /// the one place a command becomes a string. Every element is single-quoted
    /// first — see `Shell.commandLine`.
    ///
    /// Both are addressed by bundle id rather than by name: iTerm2 has answered to
    /// both "iTerm" and "iTerm2" across versions, and `application id` sidesteps
    /// the question.
    private func runAppleScript(command: [String], in app: TerminalApp) throws {
        let commandLine = Shell.commandLine(command)
        let source: String
        switch app {
        case .terminal:
            source = """
            tell application id "\(app.bundleIdentifier)"
                activate
                do script \(AppleScriptLiteral.quote(commandLine))
            end tell
            """
        case .iTerm2:
            source = """
            tell application id "\(app.bundleIdentifier)"
                activate
                create window with default profile command \(AppleScriptLiteral.quote(commandLine))
            end tell
            """
        default:
            throw TerminalLauncherError.launchFailed(app, "It is not driven with AppleScript.")
        }

        var errorInfo: NSDictionary?
        NSAppleScript(source: source)?.executeAndReturnError(&errorInfo)

        guard let errorInfo else { return }
        let code = errorInfo[NSAppleScript.errorNumber] as? Int ?? 0
        let message = errorInfo[NSAppleScript.errorMessage] as? String ?? "Unknown AppleScript error."

        // -1743 is "not authorised to send Apple events"; the user answered no to
        // the Automation prompt, or never saw it.
        if code == -1743 || code == errAEEventNotPermitted {
            throw TerminalLauncherError.automationDenied(app)
        }
        throw TerminalLauncherError.launchFailed(app, message)
    }

    // MARK: - Argument-vector terminals

    /// Prefers running the CLI inside the app bundle over `NSWorkspace`, because
    /// `openApplication` only forwards its `arguments` when it actually starts the
    /// app: if the terminal is already open — the usual case — they are dropped and
    /// the user gets an empty window. The bundled CLI opens a new window either way.
    /// `NSWorkspace` remains the fallback for a layout we do not recognise.
    private func launchWithArguments(command: [String], in app: TerminalApp) async throws {
        let arguments = app.arguments(toRun: command)

        if let executable = bundledExecutable(for: app) {
            do {
                _ = try ProcessRunner().run(executable, arguments: arguments, timeout: 10)
                activate(app)
                return
            } catch {
                // Fall through to NSWorkspace rather than giving up.
            }
        }

        guard let bundle = bundleURL(for: app) else { throw TerminalLauncherError.notInstalled(app) }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.arguments = arguments
        configuration.activates = true
        do {
            _ = try await workspace.openApplication(at: bundle, configuration: configuration)
        } catch {
            throw TerminalLauncherError.launchFailed(app, error.localizedDescription)
        }
    }

    private func bundledExecutable(for app: TerminalApp) -> URL? {
        guard let bundle = bundleURL(for: app) else { return nil }
        let macOS = bundle.appendingPathComponent("Contents/MacOS")
        for name in app.bundledExecutableNames {
            let candidate = macOS.appendingPathComponent(name)
            if TailscaleBinaryLocator.isUsable(candidate.path) { return candidate }
        }
        return nil
    }

    private func activate(_ app: TerminalApp) {
        workspace.runningApplications
            .first { $0.bundleIdentifier == app.bundleIdentifier }?
            .activate()
    }
}

extension TerminalApp {

    /// How each terminal spells "run this command in a new window".
    ///
    /// Only Terminal.app is verified on the development machine; the others are
    /// taken from their documented command lines. See the README's notes section.
    func arguments(toRun command: [String]) -> [String] {
        switch self {
        case .ghostty, .alacritty:
            return ["-e"] + command
        case .wezTerm:
            return ["start", "--"] + command
        case .kitty:
            // kitty takes the program as trailing arguments, with no -e.
            return command
        case .terminal, .iTerm2:
            return command
        }
    }

    /// CLI entry points inside each app bundle, best first.
    var bundledExecutableNames: [String] {
        switch self {
        case .ghostty: return ["ghostty"]
        case .wezTerm: return ["wezterm-gui", "wezterm"]
        case .kitty: return ["kitty"]
        case .alacritty: return ["alacritty"]
        case .terminal, .iTerm2: return []
        }
    }
}
