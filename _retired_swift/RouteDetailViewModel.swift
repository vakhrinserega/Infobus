//
//  RouteDetailViewModel.swift
//  Infobus
//
//  Drives the mnemoscheme: which direction's stop order is shown, live bus
//  positions along that order, arrival predictions, and which station is
//  nearest the rider right now.
//
//  Predictions: fetched one station at a time, on demand — mirrors the old
//  Objective-C app's own `/stations/{id}/prediction` usage (one tap, one
//  station), rather than eagerly polling every stop on the route at once
//  (which the old app never did either, and which doesn't scale to routes
//  with 20-40 stops). The one exception is the rider's OWN current station,
//  which auto-refreshes on the same 15s cadence as live buses, so the inline
//  ETA under that one row stays live without adding N-1 extra requests.
//
//  Bus direction: Route exposes only ONE physical polyline (confirmed
//  against the old Objective-C client, which has no second polyline either),
//  and Bus.direction is an unverified field — undocumented whether it means
//  "which of the route's two directions" versus "compass heading for
//  rotating an icon" (the old app only ever used it for the latter). So
//  instead of trusting that field, each bus's direction is inferred from
//  its OWN movement: comparing its position along the polyline between two
//  consecutive polls (15s apart) tells us, empirically, which way it's
//  actually going. This assumes the "forward" direction's stop sequence
//  runs in the same order as increasing position along the polyline — true
//  for a typical out-and-back route, but unverified against real traffic
//  since every live sample fetched while building the API layer came back
//  empty. Worth re-checking once real bus movement is observable.
//
//  Prediction.prediction's unit is also unconfirmed (see Prediction.swift) —
//  displayed here assuming minutes.
//

import Foundation
import CoreLocation
import Combine

@MainActor
final class RouteDetailViewModel: ObservableObject {
    let route: Route
    private let city: City
    private let country: Country
    private let cache: CityDataCache
    private let apiClient: InfobusAPIClient

    @Published var direction: RouteDirection = .forward
    @Published var stopsState: LoadState<[RouteStop]> = .idle
    @Published var buses: [PositionedBus] = []
    @Published var currentStationId: Int?
    /// Predictions for the rider's current station only. Every other
    /// station's predictions are fetched on demand via `fetchPredictions(stationId:)`
    /// when its row is tapped — see the header for why this isn't done for
    /// every stop at once.
    @Published var currentStationPredictions: [Prediction] = []

    private var stationsById: [Int: Station] = [:]
    private var linksForRoute: [RouteStationLink] = []
    private var pollingTask: Task<Void, Never>?

    /// Each bus's position (0...1 along the route polyline) as of the last
    /// poll, keyed by Bus.id — the only way to tell which physical direction
    /// it's moving, since Bus.direction itself isn't trustworthy for that
    /// (see header).
    private var lastFractionByBusId: [String: Double] = [:]

    /// Below this much change in fraction between two polls, treat the bus
    /// as parked/stuck rather than guessing a direction from GPS jitter.
    private let directionNoiseThreshold: Double = 0.0015

    init(route: Route, city: City, country: Country, cache: CityDataCache = .shared, apiClient: InfobusAPIClient = .shared) {
        self.route = route
        self.city = city
        self.country = country
        self.cache = cache
        self.apiClient = apiClient
    }

    // MARK: - Stops

    func loadStops() async {
        stopsState = .loading
        do {
            let data = try await cache.refreshIfNeeded(for: city, in: country)
            stationsById = Dictionary(uniqueKeysWithValues: data.stations.map { ($0.id, $0) })
            // RouteStationLink.routeId, Bus's URL routeId, and Prediction.routeId all
            // key off the live-tracking subsystem's id ("busreportRouteId" on the wire),
            // NOT the routes CMS's own primary id — confirmed against both the old
            // Objective-C client and live production data. Route.id alone matched
            // nothing here, which is exactly the "no stops found" bug this fixes.
            linksForRoute = data.links.filter { $0.routeId == route.busreportRouteId }
            stopsState = .loaded(buildStops())
        } catch {
            stopsState = .failed("Не удалось загрузить остановки")
        }
    }

    /// Called when the direction tab changes — no network call, just
    /// re-filters/sorts the already-loaded links.
    func directionChanged() {
        guard case .loaded = stopsState else { return }
        stopsState = .loaded(buildStops())
    }

    private func buildStops() -> [RouteStop] {
        let wantsForward = direction == .forward
        return linksForRoute
            .filter { $0.directionForward == wantsForward }
            .sorted { $0.sequenceNumber < $1.sequenceNumber }
            .compactMap { link -> RouteStop? in
                guard let station = stationsById[link.stationId] else { return nil }
                let projected = RouteGeometry.project(station.coordinate, onto: route.coordinates)
                return RouteStop(station: station, sequenceNumber: link.sequenceNumber, fraction: projected?.fraction ?? 0)
            }
    }

    // MARK: - Predictions

    /// On-demand fetch for a single station — used both by the tap-to-detail
    /// sheet (any station) and by the current-station auto-refresh below.
    func fetchPredictions(stationId: Int) async -> [Prediction] {
        let routeId = route.busreportRouteId
        let predictions = (try? await apiClient.fetchPredictions(for: city, stationId: stationId)) ?? []
        return predictions.filter { $0.routeId == routeId }
    }

    private func refreshCurrentStationPredictions() async {
        guard let stationId = currentStationId else {
            currentStationPredictions = []
            return
        }
        currentStationPredictions = await fetchPredictions(stationId: stationId)
    }

    // MARK: - Live buses

    /// Starts polling immediately and every 15s after, until `stopPolling()`
    /// is called. Each tick refreshes both live buses and (if the rider's
    /// current station is known) that one station's predictions — a single
    /// shared cadence rather than two independent timers.
    func startPolling() {
        guard pollingTask == nil else { return }
        pollingTask = Task {
            while !Task.isCancelled {
                async let busesRefresh: Void = refreshBuses()
                async let predictionsRefresh: Void = refreshCurrentStationPredictions()
                _ = await (busesRefresh, predictionsRefresh)
                try? await Task.sleep(nanoseconds: 15_000_000_000)
            }
        }
    }

    func stopPolling() {
        pollingTask?.cancel()
        pollingTask = nil
    }

    private func refreshBuses() async {
        guard let fetched = try? await apiClient.fetchBuses(for: city, routeId: route.busreportRouteId) else { return }
        let polyline = route.coordinates
        var updatedFractions: [String: Double] = [:]
        buses = fetched.compactMap { bus -> PositionedBus? in
            guard let projected = RouteGeometry.project(bus.coordinate, onto: polyline) else { return nil }
            updatedFractions[bus.id] = projected.fraction
            return PositionedBus(
                bus: bus,
                fraction: projected.fraction,
                isOffRoute: projected.distance > PositionedBus.offRouteThresholdMeters,
                travelDirection: travelDirection(busId: bus.id, newFraction: projected.fraction)
            )
        }
        lastFractionByBusId = updatedFractions
    }

    /// nil the first time a bus is seen (nothing to compare against yet) or
    /// while it's essentially stationary — otherwise .forward/.backward
    /// depending on whether it's moving toward increasing or decreasing
    /// position along the polyline. See header for the assumption this
    /// rests on.
    private func travelDirection(busId: String, newFraction: Double) -> RouteDirection? {
        guard let previous = lastFractionByBusId[busId] else { return nil }
        let delta = newFraction - previous
        guard abs(delta) > directionNoiseThreshold else { return nil }
        return delta > 0 ? .forward : .backward
    }

    /// Where each live bus that belongs on the CURRENTLY DISPLAYED direction
    /// falls between two adjacent stops in `stops` — buses with an unknown
    /// travel direction (just appeared, no trend yet) are shown on both
    /// tabs, so a newly-spotted bus is visible immediately rather than
    /// waiting out its first 15s poll interval invisibly.
    func placedBuses(for stops: [RouteStop]) -> [PlacedBus] {
        guard stops.count >= 2 else { return [] }
        let relevant = buses.filter { $0.travelDirection == nil || $0.travelDirection == direction }
        return relevant.map { positioned in
            for i in 0..<(stops.count - 1) {
                let a = stops[i].fraction
                let b = stops[i + 1].fraction
                let inRange = (a <= positioned.fraction && positioned.fraction <= b)
                    || (b <= positioned.fraction && positioned.fraction <= a)
                if inRange {
                    let span = b - a
                    let t = span == 0 ? 0 : (positioned.fraction - a) / span
                    return PlacedBus(bus: positioned.bus, isOffRoute: positioned.isOffRoute, beforeIndex: i, t: t, travelDirection: positioned.travelDirection)
                }
            }
            // Falls before the first stop or past the last — clamp to whichever
            // end is nearer, and mark it uncertain regardless of its own flag,
            // since "off the ends of what we're displaying" is its own kind of
            // not-really-placed.
            let firstFraction = stops.first!.fraction
            let lastFraction = stops.last!.fraction
            let distanceToFirst = abs(positioned.fraction - firstFraction)
            let distanceToLast = abs(positioned.fraction - lastFraction)
            if distanceToFirst <= distanceToLast {
                return PlacedBus(bus: positioned.bus, isOffRoute: true, beforeIndex: 0, t: 0, travelDirection: positioned.travelDirection)
            } else {
                return PlacedBus(bus: positioned.bus, isOffRoute: true, beforeIndex: stops.count - 2, t: 1, travelDirection: positioned.travelDirection)
            }
        }
    }

    // MARK: - Current station

    /// Nearest stop (straight-line distance to the station itself, not a
    /// polyline projection — this is "which stop is the rider closest to",
    /// a different question from where a bus sits between two stops).
    /// Kicks off an immediate prediction refresh when it actually changes,
    /// rather than waiting for the next 15s poll tick.
    func updateCurrentStation(from coordinate: CLLocationCoordinate2D) {
        guard case .loaded(let stops) = stopsState, !stops.isEmpty else { return }
        let nearest = stops.min { a, b in
            RouteGeometry.distance(a.station.coordinate, coordinate) < RouteGeometry.distance(b.station.coordinate, coordinate)
        }
        guard let nearestId = nearest?.station.id, nearestId != currentStationId else { return }
        currentStationId = nearestId
        Task { await refreshCurrentStationPredictions() }
    }
}
