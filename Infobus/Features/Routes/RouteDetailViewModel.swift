//
//  RouteDetailViewModel.swift
//  Infobus
//
//  Drives the mnemoscheme: which direction's stop order is shown, live bus
//  positions along that order, per-station arrival predictions, and which
//  station is nearest the rider right now.
//
//  Known simplifications, to revisit once real bus data is observable
//  (every live sample fetched while building the API layer came back
//  empty, so none of this could be tested against a real payload):
//   - Buses aren't filtered by Bus.direction. It's undocumented whether
//     that field even means "which of the route's two directions" as
//     opposed to "compass heading for rotating an icon" — the latter seems
//     at least as likely for a moving vehicle, and Route only exposes ONE
//     physical polyline (not a separate one per direction), so there's no
//     firm way to assign a bus to a direction from the fields we have.
//     Every bus returned for this route is shown regardless of which
//     direction tab is selected.
//   - Prediction.prediction's unit is unconfirmed (see Prediction.swift) —
//     displayed here assuming minutes.
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
    @Published var predictionsByStationId: [Int: [Prediction]] = [:]
    @Published var currentStationId: Int?

    private var stationsById: [Int: Station] = [:]
    private var linksForRoute: [RouteStationLink] = []
    private var pollingTask: Task<Void, Never>?
    /// Guards against a slow fetch for a direction the user has already
    /// switched away from landing after a newer one and overwriting its
    /// results — same pattern used for the city picker's country/city lists.
    private var predictionsRequestToken = UUID()

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
            await loadPredictions()
        } catch {
            stopsState = .failed("Не удалось загрузить остановки")
        }
    }

    /// Called when the direction tab changes — no network call, just
    /// re-filters/sorts the already-loaded links, then refetches predictions
    /// for the newly-visible set of stations.
    func directionChanged() {
        guard case .loaded = stopsState else { return }
        stopsState = .loaded(buildStops())
        Task { await loadPredictions() }
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

    private func loadPredictions() async {
        guard case .loaded(let stops) = stopsState else { return }
        let token = UUID()
        predictionsRequestToken = token
        let routeId = route.busreportRouteId
        let apiClient = self.apiClient
        let city = self.city

        await withTaskGroup(of: (Int, [Prediction]).self) { group in
            for stop in stops {
                let stationId = stop.station.id
                group.addTask {
                    let predictions = (try? await apiClient.fetchPredictions(for: city, stationId: stationId)) ?? []
                    return (stationId, predictions.filter { $0.routeId == routeId })
                }
            }
            for await (stationId, predictions) in group {
                guard predictionsRequestToken == token else { continue }
                predictionsByStationId[stationId] = predictions
            }
        }
    }

    // MARK: - Live buses

    /// Starts polling immediately and every 15s after, until `stopPolling()`
    /// is called — mirrors the "fixed short interval while a relevant screen
    /// is visible" policy agreed for bus refresh.
    func startPolling() {
        guard pollingTask == nil else { return }
        pollingTask = Task {
            while !Task.isCancelled {
                await refreshBuses()
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
        buses = fetched.compactMap { bus -> PositionedBus? in
            guard let projected = RouteGeometry.project(bus.coordinate, onto: polyline) else { return nil }
            return PositionedBus(
                bus: bus,
                fraction: projected.fraction,
                isOffRoute: projected.distance > PositionedBus.offRouteThresholdMeters
            )
        }
    }

    /// Where each live bus falls between two adjacent stops in `stops`
    /// (the CURRENTLY DISPLAYED direction's order) — recomputed on every
    /// call since it depends on that order, not just the bus's own fraction.
    func placedBuses(for stops: [RouteStop]) -> [PlacedBus] {
        guard stops.count >= 2 else { return [] }
        return buses.map { positioned in
            for i in 0..<(stops.count - 1) {
                let a = stops[i].fraction
                let b = stops[i + 1].fraction
                let inRange = (a <= positioned.fraction && positioned.fraction <= b)
                    || (b <= positioned.fraction && positioned.fraction <= a)
                if inRange {
                    let span = b - a
                    let t = span == 0 ? 0 : (positioned.fraction - a) / span
                    return PlacedBus(bus: positioned.bus, isOffRoute: positioned.isOffRoute, beforeIndex: i, t: t)
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
                return PlacedBus(bus: positioned.bus, isOffRoute: true, beforeIndex: 0, t: 0)
            } else {
                return PlacedBus(bus: positioned.bus, isOffRoute: true, beforeIndex: stops.count - 2, t: 1)
            }
        }
    }

    // MARK: - Current station

    /// Nearest stop (straight-line distance to the station itself, not a
    /// polyline projection — this is "which stop is the rider closest to",
    /// a different question from where a bus sits between two stops).
    func updateCurrentStation(from coordinate: CLLocationCoordinate2D) {
        guard case .loaded(let stops) = stopsState, !stops.isEmpty else { return }
        let nearest = stops.min { a, b in
            RouteGeometry.distance(a.station.coordinate, coordinate) < RouteGeometry.distance(b.station.coordinate, coordinate)
        }
        currentStationId = nearest?.station.id
    }
}
