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
    @Published var resultsState: LoadState<[SearchResultItem]> = .idle

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
            resultsState = .loaded(results)
        } catch {
            resultsState = .failed("Не удалось найти маршрут между этими точками")
        }
    }
}
