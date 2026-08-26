//
//  RoutesListViewModel.swift
//  Infobus
//
//  Reads the selected city's routes through CityDataCache (cache-first,
//  refreshing only if stale) rather than calling the API directly — this is
//  the same cache Settings' city picker populates on selection, so switching
//  to this tab right after picking a city should already show current data.
//

import Foundation
import Combine

@MainActor
final class RoutesListViewModel: ObservableObject {
    @Published var state: LoadState<[Route]> = .idle

    private let cache: CityDataCache

    init(cache: CityDataCache = .shared) {
        self.cache = cache
    }

    func load(city: City, country: Country) async {
        state = .loading
        do {
            let data = try await cache.refreshIfNeeded(for: city, in: country)
            let sorted = data.routes.sorted {
                $0.routeNumber.localizedStandardCompare($1.routeNumber) == .orderedAscending
            }
            state = .loaded(sorted)
        } catch {
            state = .failed("Не удалось загрузить маршруты")
        }
    }
}
