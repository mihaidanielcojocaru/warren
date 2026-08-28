//
//  PreferencesView.swift
//  Warren
//

import ServiceManagement
import SwiftUI

struct PreferencesView: View {

    @ObservedObject var preferences: Preferences
    @ObservedObject var store: DeviceStore
    let terminalLauncher: TerminalLaunching

    var body: some View {
        TabView {
            general
                .tabItem { Label("General", systemImage: "gearshape") }
            devices
                .tabItem { Label("Devices", systemImage: "desktopcomputer") }
            advanced
                .tabItem { Label("Advanced", systemImage: "wrench.and.screwdriver") }
        }
        .frame(width: 470, height: 360)
    }

    // MARK: - General

    private var general: some View {
        Form {
            Section {
                TextField("Default user name", text: $preferences.defaultUsername)
                    .textContentType(.username)

                Picker("Clicking a device", selection: $preferences.clickAction) {
                    ForEach(ClickAction.allCases) { action in
                        Text(action.displayName).tag(action)
                    }
                }

                terminalPicker
            } footer: {
                Text("Warren never handles passwords or keys — it hands the connection to ssh.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                LaunchAtLoginToggle(preferences: preferences)
            }
        }
        .formStyle(.grouped)
    }

    private var terminalPicker: some View {
        let installed = terminalLauncher.installedTerminals()
        return Picker("Terminal", selection: $preferences.terminalApp) {
            Text("Automatic").tag(TerminalApp?.none)
            ForEach(installed) { app in
                Text(app.displayName).tag(TerminalApp?.some(app))
            }
        }
        .help(installed.isEmpty
              ? "No supported terminal was found."
              : "Automatic picks the first installed: " + installed.map(\.displayName).joined(separator: ", "))
    }

    // MARK: - Devices

    private var devices: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Per-device user names")
                .font(.headline)
            Text("Leave a field empty to use the default (\(preferences.defaultUsername)).")
                .font(.caption)
                .foregroundStyle(.secondary)

            if let peers = store.snapshot?.peers, !peers.isEmpty {
                List {
                    ForEach(peers) { device in
                        overrideRow(for: device)
                    }
                }
                .listStyle(.inset)
            } else {
                Spacer()
                Text("No devices to configure yet.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                Spacer()
            }
        }
        .padding()
    }

    /// Overrides are keyed by DNS name, so a device without one cannot have one.
    @ViewBuilder
    private func overrideRow(for device: Device) -> some View {
        if let dnsName = device.dnsName {
            HStack {
                Image(systemName: device.os.symbolName)
                    .foregroundStyle(.secondary)
                    .frame(width: 18)
                Text(device.displayName)
                    .frame(width: 140, alignment: .leading)
                    .lineLimit(1)
                TextField(preferences.defaultUsername, text: binding(forDNSName: dnsName))
                    .textFieldStyle(.roundedBorder)
            }
        }
    }

    private func binding(forDNSName dnsName: String) -> Binding<String> {
        Binding(
            get: { preferences.usernameOverrides[dnsName] ?? "" },
            set: { preferences.setUsernameOverride($0, forDNSName: dnsName) }
        )
    }

    // MARK: - Advanced

    private var advanced: some View {
        Form {
            Section("Polling") {
                VStack(alignment: .leading) {
                    Slider(
                        value: $preferences.pollInterval,
                        in: Preferences.pollIntervalRange,
                        step: 1
                    ) {
                        Text("Refresh every")
                    } minimumValueLabel: {
                        Text("5s").font(.caption)
                    } maximumValueLabel: {
                        Text("60s").font(.caption)
                    }
                    Text("Every \(Int(preferences.pollInterval)) seconds while the menu is open, and once a minute while it is closed.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Tailscale command line tool") {
                HStack {
                    TextField("Automatic", text: $preferences.tailscaleBinaryPath)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                    Button("Browse…") {
                        if let path = BinaryChooser.chooseTailscaleBinary(
                            startingAt: preferences.tailscaleBinaryPath
                        ) {
                            preferences.tailscaleBinaryPath = path
                        }
                    }
                }
                binaryStatus
            }
        }
        .formStyle(.grouped)
    }

    @ViewBuilder
    private var binaryStatus: some View {
        if let url = preferences.resolvedTailscaleURL() {
            Label {
                Text(preferences.tailscaleBinaryPath.isEmpty ? "Found at \(url.path)" : "Ready")
                    .font(.caption)
            } icon: {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            }
        } else {
            Label {
                Text(preferences.tailscaleBinaryPath.isEmpty
                     ? "Not found in any of the usual locations."
                     : "That file is missing or is not executable.")
                    .font(.caption)
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            }
        }
    }
}

/// Reads its value back from the login item registration rather than from a
/// stored flag, so switching it off in System Settings is reflected here.
private struct LaunchAtLoginToggle: View {
    @ObservedObject var preferences: Preferences
    @State private var isOn = SMAppService.mainApp.status == .enabled

    var body: some View {
        Toggle("Launch at login", isOn: $isOn)
            .onChange(of: isOn) { _, newValue in
                do {
                    try preferences.setLaunchAtLogin(newValue)
                } catch {
                    AlertPresenter.show(error: error)
                    isOn = SMAppService.mainApp.status == .enabled
                }
            }
    }
}
