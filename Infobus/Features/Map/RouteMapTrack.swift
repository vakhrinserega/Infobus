//
//  RouteMapTrack.swift
//  Infobus
//
//  Live map data for ONE route: its stations, live buses snapped onto the
//  route line (or left at their raw GPS fix when too far off to plausibly
//  belong to it), and the rider's own nearest station. Shared by both the
//  single-route screen (Routes list → tap a route) and the multi-route
//  "Карта" tab (up to 5 of these running at once, one per selected route).
//
//  Replaces the earlier vertical mnemoscheme's ViewModel. That screen split
//  stations into "Туда"/"Обратно" tabs and struggled to say which tab a
//  live bus belonged in. A real map sidesteps the question: every stop sits
//  at its true position regardless of which direction's stop sequence it
//  came from, and — once real bus data was actually observable — Bus's own
//  `direction` field turned out to be exactly the compass heading needed to
//  point its icon the right way, so there's no need to infer travel
//  direction from successive GPS fixes at all (an earlier version of this
//  file did that, and it produced visibly wrong-looking directions on
//  curves/turns — using the field directly is both simpler and correct).
//
//  Buses are polled every 5s while a relevant screen is visible.
//

import Foundation
import CoreLocation
import Combine

/// One row in a station's prediction list: a route that actually serves
/// this stop, paired with one of its arrival estimates. A stop can be
/// served by several routes, and a single route can have more than one bus
/// inbound — so this is not one row per physical bus. See
/// StationPredictionSheet's header for why that distinction matters.
struct StationPredictionRow: Identifiable {
    let id = UUID()
    let routeNumber: String
    let prediction: Prediction
}

@MainActor
final class RouteMapTrack: ObservableObject, Identifiable {
    let route: Route
    private let city: City
    private let country: Country
    private let cache: CityDataCache
    private let apiClient: InfobusAPIClient

    @Published var stopsState: LoadState<[Station]> = .idle
    @Published var buses: [MapBusPin] = []
    @Published var currentStationId: Int?

    private var pollingTask: Task<Void, Never>?

    var id: Int { route.busreportRouteId }

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
            let stationsById = Dictionary(uniqueKeysWithValues: data.stations.map { ($0.id, $0) })
            // RouteStationLink.routeId, like Bus's and Prediction's, keys off
            // busreportRouteId, not Route.id. Both directions' links are
            // pooled together — a map shows every physical stop at its real
            // position, so there's no need to keep two separate direction-
            // ordered lists the way the old mnemoscheme did.
            let stationIds = Set(
                data.links
                    .filter { $0.routeId == route.busreportRouteId }
                    .map(\.stationId)
            )
            stopsState = .loaded(stationIds.compactMap { stationsById[$0] })
        } catch {
            stopsState = .failed("Не удалось загрузить остановки")
        }
    }

    // MARK: - Predictions

    /// On-demand fetch for a single station — every prediction for every
    /// route that actually serves this stop, not just this track's own
    /// route. A stop is usually shared by several routes, and the old app
    /// showed all of them together (its own "which routes stop here" table
    /// lookup), so this mirrors that rather than narrowing to one route.
    /// Route numbers are resolved against the same cached city data
    /// `loadStops()` uses, keyed by `Route.busreportRouteId` — what
    /// `Prediction.routeId` actually refers to on the wire.
    func fetchPredictions(stationId: Int) async -> [StationPredictionRow] {
        async let predictionsResult = apiClient.fetchPredictions(for: city, stationId: stationId)
        let cityData = try? await cache.refreshIfNeeded(for: city, in: country)
        let routesById = Dictionary(uniqueKeysWithValues: (cityData?.routes ?? []).map { ($0.busreportRouteId, $0) })
        let predictions = (try? await predictionsResult) ?? []

        return predictions
            .sorted { $0.prediction < $1.prediction }
            .map { prediction in
                StationPredictionRow(
                    routeNumber: routesById[prediction.routeId]?.routeNumber ?? "—",
                    prediction: prediction
                )
            }
    }

    // MARK: - Live buses

    /// Starts polling immediately and every 5s after, until `stopPolling()`
    /// is called.
    func startPolling() {
        guard pollingTask == nil else { return }
        pollingTask = Task {
            while !Task.isCancelled {
                await refreshBuses()
                try? await Task.sleep(nanoseconds: 5_000_000_000)
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
        buses = fetched.compactMap { bus -> MapBusPin? in
            guard let projected = RouteGeometry.project(bus.coordinate, onto: polyline) else { return nil }
            let isOffRoute = projected.distance > MapBusPin.offRouteThresholdMeters
            let renderCoordinate = isOffRoute
                ? bus.coordinate
                : (RouteGeometry.coordinate(atFraction: projected.fraction, along: polyline) ?? bus.coordinate)
            return MapBusPin(
                bus: bus,
                coordinate: renderCoordinate,
                isOffRoute: isOffRoute,
                bearing: bus.direction.map(Double.init)
            )
        }
    }

    // MARK: - Current station

    /// Nearest stop (straight-line distance to the station itself) to the
    /// rider's live location — highlighted distinctly on the map.
    func updateCurrentStation(from coordinate: CLLocationCoordinate2D) {
        guard case .loaded(let stations) = stopsState, !stations.isEmpty else { return }
        let nearest = stations.min { a, b in
            RouteGeometry.distance(a.coordinate, coordinate) < RouteGeometry.distance(b.coordinate, coordinate)
        }
        currentStationId = nearest?.id
    }
}
