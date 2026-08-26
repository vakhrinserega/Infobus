//
//  CityDataCache.swift
//  Infobus
//
//  On-disk cache of one city's routes/stations/route-station links. A plain
//  JSON file rather than SwiftData/CoreData: this data is read far more often
//  than it changes, refreshed wholesale per city (never queried or mutated
//  row-by-row on device), and modest in size for a single city — a JSON blob
//  is simpler to reason about now, and nothing stops a later migration to
//  SwiftData if on-device querying ever becomes necessary.
//
//  Refreshes only happen on city selection or a stale cold-launch read — never
//  on a periodic timer, per the "refresh at natural moments" decision for
//  route/station data (buses are handled separately, polled live while a
//  relevant screen is visible).
//
//  Cache files are keyed by (countryId, cityId), not city id alone: cities
//  are fetched per-country (`/countries/{id}/cities`), so nothing guarantees
//  city ids are unique *across* countries — keying by city id alone risked
//  two different cities in different countries silently sharing one cache
//  file, or a "same city" false-negative suppressing a needed refresh.
//

import Foundation

struct CityData: Codable {
    let routes: [Route]
    let stations: [Station]
    let links: [RouteStationLink]
    let lastUpdated: Date
}

actor CityDataCache {
    static let shared = CityDataCache()

    static let defaultMaxAge: TimeInterval = 24 * 60 * 60

    private let apiClient: InfobusAPIClient
    private let fileManager: FileManager

    init(apiClient: InfobusAPIClient = .shared, fileManager: FileManager = .default) {
        self.apiClient = apiClient
        self.fileManager = fileManager
    }

    /// Returns the cache immediately if it exists and is younger than `maxAge`;
    /// otherwise fetches fresh data, caches it, and returns that.
    func refreshIfNeeded(for city: City, in country: Country, maxAge: TimeInterval = CityDataCache.defaultMaxAge) async throws -> CityData {
        if let cached = readCache(for: city, in: country), Date().timeIntervalSince(cached.lastUpdated) < maxAge {
            return cached
        }
        return try await forceRefresh(for: city, in: country)
    }

    /// Always hits the network — used right after city selection and for manual
    /// pull-to-refresh, where the point is current data regardless of cache age.
    @discardableResult
    func forceRefresh(for city: City, in country: Country) async throws -> CityData {
        async let routes = apiClient.fetchRoutes(for: city)
        async let stations = apiClient.fetchStations(for: city)
        async let links = apiClient.fetchRouteStationLinks(for: city)
        let data = try await CityData(routes: routes, stations: stations, links: links, lastUpdated: Date())
        writeCache(data, for: city, in: country)
        return data
    }

    /// Whatever is on disk right now, regardless of age — for showing something
    /// instantly while a refresh runs in the background, or when offline.
    func cachedData(for city: City, in country: Country) -> CityData? {
        readCache(for: city, in: country)
    }

    // MARK: - Disk I/O

    private func cacheURL(for city: City, in country: Country) -> URL? {
        guard let dir = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        let cacheDir = dir.appendingPathComponent("CityDataCache", isDirectory: true)
        try? fileManager.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        return cacheDir.appendingPathComponent("country-\(country.id)-city-\(city.id).json")
    }

    private func readCache(for city: City, in country: Country) -> CityData? {
        guard let url = cacheURL(for: city, in: country), let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(CityData.self, from: data)
    }

    private func writeCache(_ cityData: CityData, for city: City, in country: Country) {
        guard let url = cacheURL(for: city, in: country) else { return }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(cityData) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
