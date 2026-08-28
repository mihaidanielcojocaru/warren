//
//  Preferences.swift
//  Warren
//
//  Everything the user can change, persisted to UserDefaults.
//

import Combine
import Foundation
import ServiceManagement

/// What a plain left-click on a device row does.
enum ClickAction: String, CaseIterable, Identifiable {
    case ssh
    case fileTransfer
    case copyIPv4

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .ssh: return "Open SSH session"
        case .fileTransfer: return "Open file transfer"
        case .copyIPv4: return "Copy IPv4 address"
        }
    }
}

/// The terminals Warren knows how to drive.
///
/// Order is the auto-detection order: the first one installed wins.
enum TerminalApp: String, CaseIterable, Identifiable {
    case ghostty
    case iTerm2
    case wezTerm
    case kitty
    case alacritty
    case terminal

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .ghostty: return "Ghostty"
        case .iTerm2: return "iTerm2"
        case .wezTerm: return "WezTerm"
        case .kitty: return "Kitty"
        case .alacritty: return "Alacritty"
        case .terminal: return "Terminal"
        }
    }

    /// Used both to detect the app and to launch it.
    var bundleIdentifier: String {
        switch self {
        case .ghostty: return "com.mitchellh.ghostty"
        case .iTerm2: return "com.googlecode.iterm2"
        case .wezTerm: return "com.github.wez.wezterm"
        case .kitty: return "net.kovidgoyal.kitty"
        case .alacritty: return "org.alacritty"
        case .terminal: return "com.apple.Terminal"
        }
    }

    /// Terminal.app and iTerm2 are driven with AppleScript, which is what makes
    /// them subject to the Automation permission prompt. The rest take an
    /// argument vector.
    var usesAppleScript: Bool {
        self == .terminal || self == .iTerm2
    }
}

/// Observable, UserDefaults-backed settings.
///
/// No Keychain, and no credentials of any kind: authentication is `ssh`'s job and
/// uses the keys the user already has.
final class Preferences: ObservableObject {

    private enum Key {
        static let defaultUsername = "defaultUsername"
        static let usernameOverrides = "usernameOverrides"
        static let terminalApp = "terminalApp"
        static let clickAction = "clickAction"
        static let pollInterval = "pollInterval"
        static let tailscaleBinaryPath = "tailscaleBinaryPath"
    }

    static let pollIntervalRange: ClosedRange<Double> = 5...60

    private let defaults: UserDefaults

    @Published var defaultUsername: String {
        didSet { defaults.set(defaultUsername, forKey: Key.defaultUsername) }
    }

    /// Per-device logins, keyed by DNS name because that is the one identifier a
    /// user can recognise and that survives a node being re-keyed.
    @Published var usernameOverrides: [String: String] {
        didSet { defaults.set(usernameOverrides, forKey: Key.usernameOverrides) }
    }

    /// `nil` means "whichever is installed", re-evaluated at launch time.
    @Published var terminalApp: TerminalApp? {
        didSet { defaults.set(terminalApp?.rawValue, forKey: Key.terminalApp) }
    }

    @Published var clickAction: ClickAction {
        didSet { defaults.set(clickAction.rawValue, forKey: Key.clickAction) }
    }

    @Published var pollInterval: Double {
        didSet {
            pollInterval = min(max(pollInterval, Self.pollIntervalRange.lowerBound),
                               Self.pollIntervalRange.upperBound)
            defaults.set(pollInterval, forKey: Key.pollInterval)
        }
    }

    /// Empty means "look in the usual places". See `TailscaleBinaryLocator`.
    @Published var tailscaleBinaryPath: String {
        didSet { defaults.set(tailscaleBinaryPath, forKey: Key.tailscaleBinaryPath) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.defaultUsername = defaults.string(forKey: Key.defaultUsername) ?? NSUserName()
        self.usernameOverrides = defaults.dictionary(forKey: Key.usernameOverrides) as? [String: String] ?? [:]
        self.terminalApp = defaults.string(forKey: Key.terminalApp).flatMap(TerminalApp.init(rawValue:))
        self.clickAction = defaults.string(forKey: Key.clickAction)
            .flatMap(ClickAction.init(rawValue:)) ?? .ssh
        let storedInterval = defaults.double(forKey: Key.pollInterval)
        self.pollInterval = storedInterval == 0 ? 10 : storedInterval
        self.tailscaleBinaryPath = defaults.string(forKey: Key.tailscaleBinaryPath) ?? ""
    }

    // MARK: - Derived

    /// The login to use for a device: its override, else the default.
    func username(for device: Device) -> String {
        if let dnsName = device.dnsName, let override = usernameOverrides[dnsName],
           !override.trimmingCharacters(in: .whitespaces).isEmpty {
            return override
        }
        return defaultUsername.trimmingCharacters(in: .whitespaces).isEmpty
            ? NSUserName()
            : defaultUsername
    }

    func setUsernameOverride(_ username: String?, forDNSName dnsName: String) {
        let trimmed = username?.trimmingCharacters(in: .whitespaces) ?? ""
        if trimmed.isEmpty {
            usernameOverrides.removeValue(forKey: dnsName)
        } else {
            usernameOverrides[dnsName] = trimmed
        }
    }

    /// Resolves the configured path, or `nil` when it is set but unusable.
    func resolvedTailscaleURL() -> URL? {
        TailscaleBinaryLocator.locate(override: tailscaleBinaryPath.isEmpty ? nil : tailscaleBinaryPath)
    }

    // MARK: - Launch at login

    /// Backed by the login item registration itself rather than by a stored flag,
    /// so it stays honest when the user changes it in System Settings.
    var launchesAtLogin: Bool {
        SMAppService.mainApp.status == .enabled
    }

    func setLaunchAtLogin(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
        objectWillChange.send()
    }
}
