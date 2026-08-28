//
//  MenuPanelView.swift
//  Warren
//
//  The panel behind the status item.
//

import AppKit
import SwiftUI

struct MenuPanelView: View {

    @ObservedObject var store: DeviceStore
    @ObservedObject var actions: DeviceActions
    @ObservedObject var preferences: Preferences

    @State private var isOfflineExpanded = false

    /// Measured height of the device list. See `deviceScrollView`.
    @State private var listContentHeight: CGFloat = 0

    /// Past this the list scrolls rather than growing the panel.
    private static let maxListHeight: CGFloat = 420

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let snapshot = store.snapshot {
                header(snapshot)
                Divider().padding(.vertical, 4)
                deviceList
            } else {
                StatusMessageView(
                    state: store.state,
                    onChooseBinary: chooseBinary,
                    onOpenTailscale: openTailscaleApp
                )
            }

            Divider().padding(.vertical, 4)
            footer
        }
        .padding(6)
        .frame(width: 300)
        .onAppear { store.menuOpened() }
        .onDisappear { store.menuClosed() }
    }

    // MARK: - Header

    /// This machine, not clickable: it is a label, not a destination.
    private func header(_ snapshot: TailnetSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Text(snapshot.selfDevice?.displayName ?? "This Mac")
                    .fontWeight(.semibold)
                    .lineLimit(1)
                Spacer(minLength: 4)
                if let ipv4 = snapshot.selfDevice?.ipv4 {
                    Text(ipv4)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }
            if let exitNode = snapshot.activeExitNode {
                Text("Exit node: \(exitNode.displayName)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .menuRowInsets()
    }

    // MARK: - Devices

    @ViewBuilder
    private var deviceList: some View {
        if store.shouldShowSearchField {
            TextField("Search", text: $store.searchText)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal, 8)
                .padding(.bottom, 4)
        }

        let online = store.onlinePeers
        let offline = store.offlinePeers

        if online.isEmpty && offline.isEmpty {
            Text(emptyMessage)
                .foregroundStyle(.secondary)
                .menuRowInsets()
        } else {
            deviceScrollView(online: online, offline: offline)
        }
    }

    /// The list has to be given a real height, not just a ceiling.
    ///
    /// A `ScrollView` inside a `MenuBarExtra` window is proposed no height at all,
    /// and `maxHeight` alone then resolves to zero — the panel renders its header
    /// and footer with nothing in between. So the content is measured and the
    /// frame pinned to it, up to the cap. A plain `VStack` rather than a
    /// `LazyVStack` for the same reason: a lazy stack in a zero-height viewport
    /// builds no rows, and would measure zero forever.
    private func deviceScrollView(online: [Device], offline: [Device]) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 1) {
                ForEach(online) { device in
                    DeviceRowView(device: device, actions: actions)
                }

                if !offline.isEmpty {
                    DisclosureGroup(isExpanded: $isOfflineExpanded) {
                        ForEach(offline) { device in
                            DeviceRowView(device: device, actions: actions)
                        }
                    } label: {
                        Text("Offline (\(offline.count))")
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 10)
                    .padding(.top, 2)
                }
            }
            .background(
                GeometryReader { proxy in
                    Color.clear.preference(key: ListContentHeightKey.self, value: proxy.size.height)
                }
            )
        }
        .frame(height: min(max(listContentHeight, 1), Self.maxListHeight))
        .onPreferenceChange(ListContentHeightKey.self) { height in
            listContentHeight = height
        }
    }

    private var emptyMessage: String {
        store.searchText.isEmpty ? "No other devices in this tailnet" : "No devices match"
    }

    // MARK: - Footer

    private var footer: some View {
        VStack(alignment: .leading, spacing: 1) {
            Button {
                store.refresh()
            } label: {
                HStack {
                    Text("Refresh Now")
                    Spacer()
                    if store.isRefreshing {
                        ProgressView().controlSize(.small)
                    }
                }
            }
            .buttonStyle(MenuRowButtonStyle())

            SettingsLink {
                Text("Settings…")
            }
            .buttonStyle(MenuRowButtonStyle())

            Button("Quit \(AppInfo.name)") {
                NSApplication.shared.terminate(nil)
            }
            .buttonStyle(MenuRowButtonStyle())
        }
    }

    // MARK: - Actions

    private func chooseBinary() {
        if let path = BinaryChooser.chooseTailscaleBinary(startingAt: preferences.tailscaleBinaryPath) {
            preferences.tailscaleBinaryPath = path
        }
    }

    private func openTailscaleApp() {
        let url = URL(fileURLWithPath: "/Applications/Tailscale.app")
        if FileManager.default.fileExists(atPath: url.path) {
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
        } else if let store = URL(string: "https://tailscale.com/download") {
            NSWorkspace.shared.open(store)
        }
    }
}


/// Carries the measured height of the device list out of the scroll view.
private struct ListContentHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
