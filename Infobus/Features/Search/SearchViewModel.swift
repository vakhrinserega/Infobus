//
//  SearchViewModel.swift
//  Infobus
//
//  Backs the "Поиск" tab — pick a departure and destination point (either
//  tapped on a map or "my location"), then ask the old `pathsbwpoints`
//  endpoint which route(s) connect them. Deliberately arbitrary map points,
//  not a station picker: the endpoint takes raw coordinates and the backend
//  itself works out which nearby stops to walk to, matching what the old
//  app's own map-tap search did — picking a station up front would only
//  narrow that down artificially.
//

import Foundation
import CoreLocation
import Combine

/// A picked endpoint for the search — a coordinate plus whatever readable
/// label it resolved to (a reverse-geocoded address, "Моё местоположение",
/// or a raw "lat, lon" fallback).
struct SearchPoint {
    let coordinate: CLLocationCoordinate2D
    let label: String
}

@MainActor
final class SearchViewModel: ObservableObject {
    @Published var fromPoint: SearchPoint?
    @Published var toPoint: SearchPoint?
    @Published var resultsState: LoadState<[SearchPath]> = .idle

    /// The server can return dozens of paths for two points with lots of
    /// nearby stops (the old app capped its own page control at 10) — most
    /// riders only care about the first few best options anyway, and after
    /// sorting below, the best ones are always at the front.
    private static let maxResults = 5

    private let apiClient: InfobusAPIClient

    init(apiClient: InfobusAPIClient = .shared) {
        self.apiClient = apiClient
    }

    func reset() {
        fromPoint = nil
        toPoint = nil
        resultsState = .idle
    }

    func search(city: City) async {
        guard let fromPoint, let toPoint else { return }
        resultsState = .loading
        do {
            let results = try await apiClient.search(city: city, from: fromPoint.coordinate, to: toPoint.coordinate)
            // Direct connections first, then by how many stops are involved
            // overall — a stable sort, so paths the server considered more
            // relevant at equal leg/stop counts keep their original order.
            let sorted = results.sorted { lhs, rhs in
                if lhs.legs.count != rhs.legs.count { return lhs.legs.count < rhs.legs.count }
                return lhs.legs.reduce(0) { $0 + $1.numStops } < rhs.legs.reduce(0) { $0 + $1.numStops }
            }
            resultsState = .loaded(Array(sorted.prefix(Self.maxResults)))
        } catch {
            // A single hardcoded message regardless of cause would make a
            // genuine "no path" response and, say, a network failure read
            // identically to the rider. Surfacing the real `InfobusAPIError`
            // case (already has distinct Russian text per failure kind)
            // costs nothing and actually tells them what went wrong.
            let detail = (error as? InfobusAPIError)?.errorDescription ?? error.localizedDescription
            resultsState = .failed("Не удалось найти маршрут между этими точками (\(detail))")
        }
    }
}
