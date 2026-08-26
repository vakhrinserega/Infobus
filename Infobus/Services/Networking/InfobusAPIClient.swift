//
//  InfobusAPIClient.swift
//  Infobus
//
//  Talks to https://infobus.kz — a small master directory (countries,
//  cities) plus, per city, a `serviceURL`-scoped set of endpoints (routes,
//  stations, live buses, predictions, search, and a fire-and-forget
//  statistics beacon). All city-scoped calls are built against that city's
//  own serviceURL, never a hardcoded host, since the data model allows
//  different cities to be served by different backends.
//
//  An actor, so concurrent screens sharing `.shared` can't race each other
//  inside the client itself; each call is still an independent request.
//

import Foundation
import CoreLocation

actor InfobusAPIClient {
    static let shared = InfobusAPIClient()

    private let session: URLSession
    private let decoder: JSONDecoder
    private let masterBaseURL = URL(string: "https://infobus.kz/api")!

    /// Unreserved characters only (RFC 3986) — safe to embed unescaped in an
    /// `application/x-www-form-urlencoded` body. `.urlQueryAllowed` is NOT safe
    /// here: it lets `&`, `=`, and `+` through unescaped, which would corrupt
    /// the hand-built body below if a route/station name contained any.
    private static let formValueAllowedCharacters: CharacterSet = {
        CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")
    }()

    init(session: URLSession = .shared) {
        self.session = session
        self.decoder = JSONDecoder()
    }

    // MARK: - Master directory

    func fetchCountries() async throws -> [Country] {
        try await get(masterBaseURL.appendingPathComponent("countries"))
    }

    func fetchCities(countryId: Int) async throws -> [City] {
        try await get(masterBaseURL.appendingPathComponent("countries/\(countryId)/cities"))
    }

    // MARK: - Per-city endpoints

    func fetchCityInfo(_ city: City) async throws -> CityInfo {
        let base = try serviceBaseURL(for: city)
        return try await get(base.appendingPathComponent("api/cities/\(city.id)"))
    }

    func fetchRoutes(for city: City) async throws -> [Route] {
        let base = try serviceBaseURL(for: city)
        return try await get(base.appendingPathComponent("cities/\(city.id)/routes"))
    }

    func fetchStations(for city: City) async throws -> [Station] {
        let base = try serviceBaseURL(for: city)
        return try await get(base.appendingPathComponent("cities/\(city.id)/stations"))
    }

    func fetchRouteStationLinks(for city: City) async throws -> [RouteStationLink] {
        let base = try serviceBaseURL(for: city)
        return try await get(base.appendingPathComponent("cities/\(city.id)/routestations"))
    }

    func fetchBuses(for city: City, routeId: Int) async throws -> [Bus] {
        let base = try serviceBaseURL(for: city)
        return try await get(base.appendingPathComponent("cities/\(city.id)/routes/\(routeId)/busses"))
    }

    func fetchPredictions(for city: City, stationId: Int) async throws -> [Prediction] {
        let base = try serviceBaseURL(for: city)
        return try await get(base.appendingPathComponent("cities/\(city.id)/stations/\(stationId)/prediction"))
    }

    func search(city: City, from: CLLocationCoordinate2D, to: CLLocationCoordinate2D) async throws -> [SearchResultItem] {
        let base = try serviceBaseURL(for: city)
        guard var components = URLComponents(url: base.appendingPathComponent("cities/\(city.id)/pathsbwpoints"), resolvingAgainstBaseURL: false) else {
            throw InfobusAPIError.invalidURL
        }
        components.queryItems = [
            URLQueryItem(name: "sourceLat", value: String(format: "%.6f", from.latitude)),
            URLQueryItem(name: "sourceLng", value: String(format: "%.6f", from.longitude)),
            URLQueryItem(name: "targetLat", value: String(format: "%.6f", to.latitude)),
            URLQueryItem(name: "targetLng", value: String(format: "%.6f", to.longitude))
        ]
        guard let url = components.url else { throw InfobusAPIError.invalidURL }
        return try await get(url)
    }

    /// Fire-and-forget usage beacon the old app sent when a user picked a route. Best-effort:
    /// failures are swallowed since this is telemetry, not user-facing functionality.
    func postStatistic(city: City, routeId: Int, routeName: String, deviceId: String) async {
        await postStatistic(city: city, idParam: "rid", idValue: routeId, nameParam: "rn", nameValue: routeName, deviceId: deviceId)
    }

    /// Same beacon, for picking a station instead of a route.
    func postStatistic(city: City, stationId: Int, stationName: String, deviceId: String) async {
        await postStatistic(city: city, idParam: "sid", idValue: stationId, nameParam: "sn", nameValue: stationName, deviceId: deviceId)
    }

    // MARK: - Private helpers

    private func serviceBaseURL(for city: City) throws -> URL {
        guard let url = URL(string: city.serviceURL) else { throw InfobusAPIError.invalidURL }
        return url
    }

    private func get<T: Decodable>(_ url: URL) async throws -> T {
        let (data, response) = try await performRequest(url)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw InfobusAPIError.serverError(statusCode: code)
        }
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw InfobusAPIError.decodingFailed(underlying: error)
        }
    }

    private func performRequest(_ url: URL) async throws -> (Data, URLResponse) {
        do {
            return try await session.data(from: url)
        } catch {
            throw InfobusAPIError.network(underlying: error)
        }
    }

    private func postStatistic(city: City, idParam: String, idValue: Int, nameParam: String, nameValue: String, deviceId: String) async {
        guard let base = try? serviceBaseURL(for: city) else { return }
        var request = URLRequest(url: base.appendingPathComponent("statistic/add"))
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let encodedName = nameValue.addingPercentEncoding(withAllowedCharacters: Self.formValueAllowedCharacters) ?? nameValue
        let body = "cid=\(city.id)&\(idParam)=\(idValue)&\(nameParam)=\(encodedName)&imei=\(deviceId)"
        request.httpBody = body.data(using: .utf8)
        _ = try? await session.data(for: request)
    }
}
