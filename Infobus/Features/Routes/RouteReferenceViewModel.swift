//
//  RouteReferenceViewModel.swift
//  Infobus
//
//  Loads one route's stop sequence, split by direction, from the same
//  cached city data RouteMapTrack uses for the live map — just kept in its
//  original per-direction order here (sequenceNumber) instead of pooled
//  into one unordered set of station ids, since a reference view needs to
//  say "which stop comes after which," not just "which stops exist."
//
//  There's no schedule/interval data anywhere in the API (checked against
//  the old Objective-C client's own DataRetrievalManager — no such endpoint
//  ever existed), so this view sticks to what's actually available: the
//  route's name/number, each direction's endpoints, and its full ordered
//  stop list.
//

import Foundation
import Combine

struct RouteDirectionStops: Identifiable {
    var id: Bool { isForward }
    let isForward: Bool
    let stations: [Station]
}

@MainActor
final class RouteReferenceViewModel: ObservableObject {
    @Published var state: LoadState<[RouteDirectionStops]> = .idle

    private let cache: CityDataCache
    private let apiClient: InfobusAPIClient

    /// Kept around from `load()` purely to resolve `Prediction.routeId` to a
    /// human-readable route number for `fetchPredictions` — same cached
    /// lookup RouteMapTrack does for the exact same reason.
    private var routesById: [Int: Route] = [:]

    init(cache: CityDataCache = .shared, apiClient: InfobusAPIClient = .shared) {
        self.cache = cache
        self.apiClient = apiClient
    }

    func load(route: Route, city: City, country: Country) async {
        state = .loading
        do {
            let data = try await cache.refreshIfNeeded(for: city, in: country)
            routesById = Dictionary(uniqueKeysWithValues: data.routes.map { ($0.busreportRouteId, $0) })
            let stationsById = Dictionary(uniqueKeysWithValues: data.stations.map { ($0.id, $0) })
            let links = data.links.filter { $0.routeId == route.busreportRouteId }

            let directions = Dictionary(grouping: links, by: \.directionForward)
                .map { isForward, links -> RouteDirectionStops in
                    let stations = links
                        .sorted { $0.sequenceNumber < $1.sequenceNumber }
                        .compactMap { stationsById[$0.stationId] }
                    return RouteDirectionStops(isForward: isForward, stations: stations)
                }
                .sorted { lhs, _ in lhs.isForward }

            state = .loaded(directions)
        } catch {
            // Reusing the exact wording RouteMapTrack already uses for the
            // same kind of failure (rather than this slightly different
            // "...маршрута" variant) — that key already has kk/en/uk
            // translations in Localizable.xcstrings, this one never did.
            state = .failed("Не удалось загрузить остановки")
        }
    }

    /// Backs the tap-to-see-predictions sheet on this screen's stop list —
    /// same "every route serving this stop, plus its arrival estimate"
    /// lookup RouteMapTrack does for map pins, just without needing a
    /// RouteMapTrack (and its live-bus polling) for a screen that's just a
    /// static reference card.
    func fetchPredictions(stationId: Int, city: City, country: Country) async -> [StationPredictionRow] {
        async let predictionsResult = apiClient.fetchPredictions(for: city, stationId: stationId)
        // routesById is normally already populated by `load()` by the time
        // a row can be tapped, but re-derive it defensively rather than
        // assume that ordering.
        if routesById.isEmpty, let cached = try? await cache.refreshIfNeeded(for: city, in: country) {
            routesById = Dictionary(uniqueKeysWithValues: cached.routes.map { ($0.busreportRouteId, $0) })
        }
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
}
