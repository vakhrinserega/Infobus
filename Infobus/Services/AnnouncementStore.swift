//
//  AnnouncementStore.swift
//  Infobus
//
//  City-wide announcements — a single admin-authored message for the
//  currently selected city, surfaced through the existing `CityInfo`
//  endpoint (`message`/`displayMessage` — see CityInfo.swift's header)
//  rather than a dedicated notifications endpoint. There's no list to page
//  through: the API only ever carries "is there one active right now", so
//  a new one simply replaces whatever was there before.
//
//  Owned at the app root (see ContentView, which drives `run(for:)` from a
//  `.task(id: cityStore.selectionKey)`) rather than by NotificationsView
//  itself — the unseen-badge on that tab's own icon needs to update while
//  some *other* tab is on screen, so the poll that feeds it has to keep
//  running independently of whether the Уведомления tab is actually
//  visible. Same reasoning as RouteMapTrack's bus poll being driven by
//  whichever screen needs it, just one level higher up the view tree.
//

import Foundation
import Combine

@MainActor
final class AnnouncementStore: ObservableObject {
    @Published private(set) var loadState: LoadState<Void> = .idle
    @Published private(set) var message: String?
    /// True when `message` is non-nil and differs from whatever was last
    /// marked seen (via `markSeen`) for this city — drives the tab badge.
    @Published private(set) var hasUnseenAnnouncement = false

    private enum Keys {
        static let lastSeenPrefix = "notifications.lastSeenMessage."
    }

    /// How often to re-check for a new/changed announcement while a city is
    /// selected — frequent enough that one written on the server shows up
    /// without the rider leaving and reopening the tab, cheap enough (one
    /// small GET, the same endpoint CityRegion already uses for map
    /// framing) that it's not worth gating behind anything fancier than a
    /// fixed interval.
    private static let pollIntervalNanoseconds: UInt64 = 25_000_000_000

    private let apiClient: InfobusAPIClient
    private let defaults: UserDefaults

    init(apiClient: InfobusAPIClient = .shared, defaults: UserDefaults = .standard) {
        self.apiClient = apiClient
        self.defaults = defaults
    }

    /// Long-running loop for one city: loads immediately, then polls every
    /// `pollIntervalNanoseconds` until cancelled. The caller is expected to
    /// run this from a `.task(id:)` keyed on the city selection — SwiftUI
    /// cancels the previous call and starts a fresh one the moment that id
    /// changes, which is exactly the "switch city, stop watching the old
    /// one's announcement" behavior this wants.
    func run(for city: City) async {
        loadState = .loading
        await load(for: city)
        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: Self.pollIntervalNanoseconds)
            guard !Task.isCancelled else { break }
            await poll(for: city)
        }
    }

    /// One-shot re-fetch for the "Повторить" button — deliberately not
    /// `run(for:)` again, which would start a *second*, independent polling
    /// loop stacked on top of the one ContentView already owns for this
    /// city.
    func retry(for city: City) async {
        loadState = .loading
        await load(for: city)
    }

    /// Call when no city is selected — clears any previous city's stale
    /// message/badge rather than leaving it on screen.
    func clear() {
        message = nil
        hasUnseenAnnouncement = false
        loadState = .idle
    }

    /// Marks the current message as seen for `cityId`, clearing the badge.
    /// NotificationsView calls this as soon as an active message is both
    /// loaded AND on screen.
    func markSeen(cityId: Int) {
        guard let message else { return }
        defaults.set(message, forKey: Keys.lastSeenPrefix + String(cityId))
        hasUnseenAnnouncement = false
    }

    // MARK: - Private

    private func load(for city: City) async {
        do {
            let info = try await apiClient.fetchCityInfo(city)
            apply(info, cityId: city.id)
            loadState = .loaded(())
        } catch {
            let detail = (error as? InfobusAPIError)?.errorDescription ?? error.localizedDescription
            loadState = .failed("Не удалось загрузить объявление (\(detail))")
        }
    }

    /// A background poll tick's failure (after the initial load already
    /// succeeded) just keeps showing whatever was last good rather than
    /// replacing it with an error screen — same spirit as RouteMapTrack's
    /// `refreshBuses()`, which silently no-ops on a failed poll instead of
    /// touching `stopsState`. A tick that *recovers* after the very first
    /// load had failed does clear that failure, though, so a rider who
    /// opened the tab during a brief outage isn't stuck on a stale retry
    /// screen once the network comes back on its own.
    private func poll(for city: City) async {
        guard let info = try? await apiClient.fetchCityInfo(city) else { return }
        apply(info, cityId: city.id)
        if case .failed = loadState {
            loadState = .loaded(())
        }
    }

    private func apply(_ info: CityInfo, cityId: Int) {
        guard info.displayMessage, !info.message.isEmpty else {
            message = nil
            hasUnseenAnnouncement = false
            return
        }
        message = info.message
        let lastSeen = defaults.string(forKey: Keys.lastSeenPrefix + String(cityId))
        hasUnseenAnnouncement = lastSeen != info.message
    }
}
