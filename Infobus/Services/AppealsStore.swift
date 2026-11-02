//
//  AppealsStore.swift
//  Infobus
//
//  The rider's own support requests ("Мои обращения") — one message, at
//  most one reply each, never a back-and-forth thread: a full chat would
//  need a much heavier backend (message ordering, read receipts, a reason
//  to keep a socket open) for little benefit over "ask once, get an
//  answer". Backed by a per-city Google Apps Script Web App rather than
//  the main infobus.kz backend — a spreadsheet as the datastore and a
//  Telegram bot as the support team's entire "admin panel": an operator
//  answers by replying (in Telegram) to the message the bot forwarded,
//  the script correlates that reply back to the right row by Telegram
//  message id, no custom admin UI to build at all.
//
//  There's no login anywhere in this app, so `DeviceIdentity.current` (a
//  random UUID generated once per install) is the only "whose appeals are
//  these" the backend can go on — see that file's header for the
//  trade-off that implies.
//
//  Retention is split deliberately: the Apps Script sheet keeps every
//  appeal indefinitely (deleted only by hand, if ever — see Code.gs),
//  while THIS store only ever shows the most recent `maxDisplayedAppeals`
//  locally. Nothing is lost either way — the cap is about keeping the
//  rider's own list short enough to actually scan, not about disk space.
//
//  Owned at the app root (ContentView), same reasoning as AnnouncementStore:
//  the unseen-reply badge on the "Уведомления" tab icon needs to update
//  while some other tab is on screen, so the poll driving it can't live
//  inside NotificationsView itself.
//

import Foundation
import Combine

@MainActor
final class AppealsStore: ObservableObject {
    @Published private(set) var loadState: LoadState<Void> = .idle
    @Published private(set) var appeals: [Appeal] = []
    /// True once this city's `CityInfo.appealsEndpoint` has resolved to a
    /// real URL — false while that's still being checked, and false (not
    /// an error) for a city where appeals simply haven't been set up yet.
    @Published private(set) var isAvailableForCity = false
    @Published private(set) var isSubmitting = false
    @Published private(set) var submitError: String?
    /// How many *answered* appeals carry a reply this device hasn't had
    /// marked seen yet (via `markSeen`) — feeds the shared tab badge
    /// alongside AnnouncementStore's own unseen flag.
    @Published private(set) var unseenAnsweredCount = 0

    private enum Keys {
        static let lastSeenAnswerPrefix = "appeals.lastSeenAnswer."
    }

    /// Appeals don't need the ~25s cadence announcements do — a reply
    /// usually isn't as time-critical as a city-wide notice, and this
    /// keeps the Apps Script side (a free-tier Google service, not a
    /// dedicated server) from being hit any harder than it needs to be.
    private static let pollIntervalNanoseconds: UInt64 = 45_000_000_000

    /// How many of this device's own appeals the APP shows at once —
    /// purely a display cap, not a retention policy: the Apps Script
    /// sheet itself keeps every appeal indefinitely now (see Code.gs —
    /// the old automatic 30-day cleanup was removed in favor of deleting
    /// manually if it's ever actually needed), so nothing is lost by
    /// capping what this list renders to the most recent few.
    private static let maxDisplayedAppeals = 5

    private let apiClient: InfobusAPIClient
    private let defaults: UserDefaults
    private var endpoint: String?
    private var cityId: Int?

    init(apiClient: InfobusAPIClient = .shared, defaults: UserDefaults = .standard) {
        self.apiClient = apiClient
        self.defaults = defaults
    }

    /// Long-running loop for one city: resolves `appealsEndpoint` from
    /// `CityInfo` once, then — if this city actually has one configured —
    /// loads the appeals list and polls it until cancelled. Meant to be
    /// driven from a `.task(id:)` keyed on the city selection (see
    /// ContentView), which cancels and restarts this the moment that id
    /// changes.
    func run(for city: City) async {
        loadState = .loading
        guard await resolveEndpoint(for: city) else {
            if case .failed = loadState { /* keep the failure + retry affordance */ } else {
                loadState = .loaded(())
            }
            return
        }
        await loadAppeals()
        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: Self.pollIntervalNanoseconds)
            guard !Task.isCancelled else { break }
            await pollAppeals()
        }
    }

    /// One-shot re-attempt for the "Повторить" button — re-resolves the
    /// endpoint too, in case the very first failure was CityInfo itself
    /// not loading, not just the appeals list.
    func retry(for city: City) async {
        loadState = .loading
        guard await resolveEndpoint(for: city) else {
            if case .failed = loadState { } else {
                loadState = .loaded(())
            }
            return
        }
        await loadAppeals()
    }

    /// Submits a new appeal and, on success, drops it straight into the
    /// list (at the top, "Ожидает ответа") instead of waiting for the
    /// next poll tick to pick it up.
    @discardableResult
    func submit(message: String, category: String? = nil, city: City) async -> Bool {
        guard let endpoint, let cityId else { return false }
        isSubmitting = true
        submitError = nil
        defer { isSubmitting = false }
        do {
            let created = try await apiClient.createAppeal(
                endpoint: endpoint,
                deviceId: DeviceIdentity.current,
                cityId: cityId,
                message: message,
                category: category
            )
            appeals.insert(created, at: 0)
            trimToDisplayLimit()
            recomputeUnseenCount()
            return true
        } catch InfobusAPIError.appealRejected(let message) {
            // The server's own message (e.g. an anti-spam cooldown/daily
            // cap — see Code.gs) is already a complete, ready-to-show
            // sentence, not a technical failure — show it as-is rather
            // than wrapping it in "Не удалось отправить обращение (...)".
            submitError = message
            return false
        } catch {
            let detail = (error as? InfobusAPIError)?.errorDescription ?? error.localizedDescription
            submitError = "Не удалось отправить обращение (\(detail))"
            return false
        }
    }

    /// Call when no city is selected — clears any previous city's appeals
    /// rather than leaving them on screen under a new selection.
    func clear() {
        endpoint = nil
        cityId = nil
        appeals = []
        isAvailableForCity = false
        unseenAnsweredCount = 0
        submitError = nil
        loadState = .idle
    }

    /// Marks one appeal's current answer as seen, clearing its
    /// contribution to the badge. Called when its detail view is opened —
    /// not just from the list row, since seeing the status chip isn't the
    /// same as having actually read the reply.
    func markSeen(_ appeal: Appeal) {
        guard let answer = appeal.answer else { return }
        defaults.set(answer, forKey: Keys.lastSeenAnswerPrefix + String(appeal.id))
        recomputeUnseenCount()
    }

    /// Whether THIS specific appeal is the one contributing to the shared
    /// badge — the tab/section-level badges only ever said "something in
    /// here changed," which wasn't enough to find which row actually got
    /// a new answer once there's more than one in the list. The row view
    /// reads this directly rather than duplicating the same check.
    func isUnseen(_ appeal: Appeal) -> Bool {
        guard appeal.status == .answered, let answer = appeal.answer else { return false }
        let seen = defaults.string(forKey: Keys.lastSeenAnswerPrefix + String(appeal.id))
        return seen != answer
    }

    // MARK: - Private

    /// Resolves `appealsEndpoint` from this city's `CityInfo`, falling
    /// back to `AppealsTestConfig.hardcodedEndpoint` (see that file) when
    /// the server doesn't supply one yet — purely a testing bridge until
    /// infobus.kz actually returns `appealsEndpoint` for real. Returns
    /// `true` only when there's a real endpoint to use (from either
    /// source); `false` covers both "this city has no appeals endpoint
    /// configured anywhere" (not an error — `isAvailableForCity` stays
    /// false, nothing else changes) and "couldn't even reach CityInfo to
    /// find out" (a real error — `loadState` is set to `.failed` so the
    /// rider gets a retry).
    private func resolveEndpoint(for city: City) async -> Bool {
        do {
            let info = try await apiClient.fetchCityInfo(city)
            let serverValue = info.appealsEndpoint?.isEmpty == false ? info.appealsEndpoint : nil
            let resolved = serverValue ?? AppealsTestConfig.hardcodedEndpoint
            guard let resolved, !resolved.isEmpty else {
                endpoint = nil
                cityId = nil
                isAvailableForCity = false
                return false
            }
            endpoint = resolved
            cityId = city.id
            isAvailableForCity = true
            return true
        } catch {
            let detail = (error as? InfobusAPIError)?.errorDescription ?? error.localizedDescription
            loadState = .failed("Не удалось загрузить обращения (\(detail))")
            return false
        }
    }

    private func loadAppeals() async {
        guard let endpoint, let cityId else { return }
        do {
            let fetched = try await apiClient.fetchAppeals(endpoint: endpoint, deviceId: DeviceIdentity.current, cityId: cityId)
            apply(fetched)
            loadState = .loaded(())
        } catch {
            let detail = (error as? InfobusAPIError)?.errorDescription ?? error.localizedDescription
            loadState = .failed("Не удалось загрузить обращения (\(detail))")
        }
    }

    /// A poll tick's failure just keeps showing whatever was last good —
    /// same reasoning as AnnouncementStore's own `poll(for:)` — except a
    /// tick that *recovers* after the first load had failed still clears
    /// that failure.
    private func pollAppeals() async {
        guard let endpoint, let cityId else { return }
        guard let fetched = try? await apiClient.fetchAppeals(endpoint: endpoint, deviceId: DeviceIdentity.current, cityId: cityId) else { return }
        apply(fetched)
        if case .failed = loadState {
            loadState = .loaded(())
        }
    }

    private func apply(_ fetched: [Appeal]) {
        appeals = fetched.sorted { $0.createdAt > $1.createdAt }
        trimToDisplayLimit()
        recomputeUnseenCount()
    }

    /// Keeps only the most recent `maxDisplayedAppeals` — always safe to
    /// call after the list is already sorted newest-first, since nothing
    /// actually gets deleted anywhere: the sheet on the server still has
    /// the rest, this is purely what's rendered here.
    private func trimToDisplayLimit() {
        if appeals.count > Self.maxDisplayedAppeals {
            appeals.removeLast(appeals.count - Self.maxDisplayedAppeals)
        }
    }

    private func recomputeUnseenCount() {
        unseenAnsweredCount = appeals.reduce(into: 0) { count, appeal in
            if isUnseen(appeal) { count += 1 }
        }
    }
}
