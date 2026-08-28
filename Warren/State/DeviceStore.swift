//
//  DeviceStore.swift
//  Warren
//
//  Owns the polling loop and the one piece of state the menu renders.
//

import Combine
import Foundation

@MainActor
final class DeviceStore: ObservableObject {

    /// A search field only earns its place once scanning the list stops being easy.
    static let searchFieldThreshold = 12

    /// While the menu is shut nobody is looking at the list, but the status icon
    /// still has to tell the truth, so polling slows down rather than stopping.
    static let idlePollInterval: TimeInterval = 60

    @Published private(set) var state: TailnetState = .loading
    @Published private(set) var isRefreshing = false

    /// Bound to the search field. Cleared whenever the menu closes.
    @Published var searchText = ""

    private let client: TailscaleClienting
    private let preferences: Preferences
    private let pollQueue = DispatchQueue(label: "com.mihaicojocaru.Warren.poll", qos: .userInitiated)
    private var timer: Timer?
    private var isMenuOpen = false
    private var cancellables = Set<AnyCancellable>()

    init(client: TailscaleClienting, preferences: Preferences) {
        self.client = client
        self.preferences = preferences

        // A changed interval should take effect now, not after the next tick.
        preferences.pollIntervalPublisher
            .removeDuplicates()
            .sink { [weak self] _ in self?.rescheduleTimer() }
            .store(in: &cancellables)
    }

    // MARK: - Lifecycle

    func start() {
        rescheduleTimer()
        refresh()
    }

    func menuOpened() {
        isMenuOpen = true
        rescheduleTimer()
        refresh()
    }

    func menuClosed() {
        isMenuOpen = false
        searchText = ""
        rescheduleTimer()
    }

    private func rescheduleTimer() {
        timer?.invalidate()
        let interval = isMenuOpen ? preferences.pollInterval : Self.idlePollInterval
        let timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        // Polling is housekeeping; let it slide rather than wake the CPU for it.
        timer.tolerance = interval * 0.2
        self.timer = timer
    }

    // MARK: - Refreshing

    func refresh() {
        guard !isRefreshing else { return }
        isRefreshing = true

        let client = self.client
        pollQueue.async {
            let result = Result { try client.fetchStatus() }
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    self.apply(result)
                    self.isRefreshing = false
                }
            }
        }
    }

    private func apply(_ result: Result<TailscaleStatus, Error>) {
        switch result {
        case .success(let status):
            state = TailnetState(snapshot: TailnetSnapshot(status: status))
        case .failure(let error):
            state = Self.state(for: error)
        }
    }

    /// Every failure gets its own calm menu item rather than an alert.
    static func state(for error: Error) -> TailnetState {
        guard let error = error as? TailscaleClientError else {
            return .unreachable(TailnetFailure(
                summary: "Can't reach the Tailscale daemon",
                detail: error.localizedDescription
            ))
        }
        switch error {
        case .binaryNotFound:
            return .binaryNotFound
        case .timedOut, .commandFailed, .unreadableOutput, .invalidTarget:
            return .unreachable(TailnetFailure(
                summary: "Can't reach the Tailscale daemon",
                detail: error.errorDescription
            ))
        }
    }

    // MARK: - Presentation helpers

    var snapshot: TailnetSnapshot? {
        if case .ready(let snapshot) = state { return snapshot }
        return nil
    }

    var shouldShowSearchField: Bool {
        (snapshot?.peers.count ?? 0) > Self.searchFieldThreshold
    }

    var onlinePeers: [Device] { filtered(snapshot?.onlinePeers ?? []) }

    var offlinePeers: [Device] { filtered(snapshot?.offlinePeers ?? []) }

    /// Matches the short name and the full DNS name, so both `nas` and
    /// `nas.tailnet-example.ts.net` find the same machine.
    private func filtered(_ devices: [Device]) -> [Device] {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return devices }
        return devices.filter { device in
            device.displayName.localizedCaseInsensitiveContains(query)
                || (device.dnsName?.localizedCaseInsensitiveContains(query) ?? false)
        }
    }
}
