//
//  AppEnvironment.swift
//  Warren
//
//  Composition root: the one place concrete implementations are chosen.
//

import Combine
import Foundation

@MainActor
final class AppEnvironment: ObservableObject {

    let preferences: Preferences
    let store: DeviceStore
    let actions: DeviceActions
    let terminalLauncher: TerminalLaunching

    private let binaryLocation: TailscaleBinaryLocation
    private var cancellables = Set<AnyCancellable>()

    init() {
        let preferences = Preferences()
        let runner = ProcessRunner()
        let binaryLocation = TailscaleBinaryLocation(url: preferences.resolvedTailscaleURL())

        let client = TailscaleClient(runner: runner, location: binaryLocation)
        let terminalLauncher = TerminalLauncher()
        let store = DeviceStore(client: client, preferences: preferences)
        let actions = DeviceActions(
            client: client,
            terminal: terminalLauncher,
            mounts: MountManager(runner: runner),
            preferences: preferences
        )
        actions.requestRefresh = { [weak store] in store?.refresh() }

        self.preferences = preferences
        self.store = store
        self.actions = actions
        self.terminalLauncher = terminalLauncher
        self.binaryLocation = binaryLocation

        // Resolving the path is main-actor work; the poll queue only ever reads the
        // result. Update before refreshing, so the retry uses the new binary.
        preferences.$tailscaleBinaryPath
            .removeDuplicates()
            .sink { [weak store] path in
                binaryLocation.update(
                    TailscaleBinaryLocator.locate(override: path.isEmpty ? nil : path)
                )
                store?.refresh()
            }
            .store(in: &cancellables)

        store.start()
    }
}
