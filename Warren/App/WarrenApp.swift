//
//  WarrenApp.swift
//  Warren
//

import SwiftUI

@main
struct WarrenApp: App {

    @StateObject private var environment = AppEnvironment()

    var body: some Scene {
        MenuBarExtra {
            MenuPanelView(
                store: environment.store,
                actions: environment.actions,
                preferences: environment.preferences
            )
        } label: {
            // A view rather than a bare Image, so the icon re-renders when the
            // backend state changes.
            MenuBarLabel(store: environment.store)
        }
        .menuBarExtraStyle(.window)

        Settings {
            PreferencesView(
                preferences: environment.preferences,
                store: environment.store,
                terminalLauncher: environment.terminalLauncher
            )
        }
    }
}

private struct MenuBarLabel: View {
    @ObservedObject var store: DeviceStore

    var body: some View {
        Image(nsImage: MenuBarIcon.image(for: store.state))
    }
}
