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

/// Shape of a rejected request from the Apps Script appeals backend —
/// its own `jsonOutput_` always answers with HTTP 200, so this is the
/// only way to tell a rejection (bad input, anti-spam rate limit) apart
/// from a real `Appeal`/`[Appeal]`. `message` is already a ready-to-show
/// Russian sentence when the server sends one; `error` is just the
/// machine-readable fallback.
private struct AppealServerError: Decodable {
    let error: String
    let message: String?
}

actor InfobusAPIClient {
    static let shared = InfobusAPIClient()

    private let session: URLSession
    private let decoder: JSONDecoder
    /// Separate from `decoder` on purpose — the Apps Script appeals
    /// backend (see Appeal.swift) returns ISO-8601 date strings, and
    /// nothing else this client decodes uses `Date` at all, so this stays
    /// scoped to just those calls rather than changing `decoder`'s
    /// behavior for every other model.
    private let appealsDecoder: JSONDecoder
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
        let appealsDecoder = JSONDecoder()
        // Plain `.iso8601` rejects the exact strings the Apps Script side
        // is expected to send: JavaScript's `Date.toISOString()` always
        // includes milliseconds ("...T12:00:00.000Z"), but Foundation's
        // built-in ISO-8601 strategy does not parse that fractional part
        // by default — every appeal would fail to decode. Try the
        // fractional-seconds formatter first, fall back to the plain one
        // in case the script ever sends a timestamp without it.
        let fractionalFormatter = ISO8601DateFormatter()
        fractionalFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let plainFormatter = ISO8601DateFormatter()
        appealsDecoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let string = try container.decode(String.self)
            if let date = fractionalFormatter.date(from: string) ?? plainFormatter.date(from: string) {
                return date
            }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unrecognized ISO-8601 date: \(string)")
        }
        self.appealsDecoder = appealsDecoder
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

    func search(city: City, from: CLLocationCoordinate2D, to: CLLocationCoordinate2D) async throws -> [SearchPath] {
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
        // The response is an array of paths, each itself an array of 1+
        // legs (a transfer) — see SearchResultItem.swift's header for how
        // this was confirmed. Decode that real shape directly, then wrap
        // each inner array as a `SearchPath`.
        let pathsOfLegs: [[SearchResultItem]] = try await get(url)
        return pathsOfLegs.map(SearchPath.init)
    }

    // MARK: - Appeals (support requests)

    /// `endpoint` is `CityInfo.appealsEndpoint` — the per-city Apps Script
    /// Web App URL, a different host entirely from `city.serviceURL` —
    /// so these two calls build their request directly from it rather
    /// than going through `serviceBaseURL(for:)`.
    func createAppeal(endpoint: String, deviceId: String, cityId: Int, message: String, category: String?) async throws -> Appeal {
        guard let url = URL(string: endpoint) else { throw InfobusAPIError.invalidURL }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var payload: [String: Any] = [
            "action": "create",
            "deviceId": deviceId,
            "cityId": cityId,
            "message": message
        ]
        if let category { payload["category"] = category }
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        return try await sendAppeal(request)
    }

    /// Every appeal this device has ever submitted for this city — the
    /// Apps Script side is expected to already be scoping/expiring these
    /// itself (the 30-day retention discussed alongside the Telegram
    /// integration), not something this client filters again.
    func fetchAppeals(endpoint: String, deviceId: String, cityId: Int) async throws -> [Appeal] {
        guard var components = URLComponents(string: endpoint) else { throw InfobusAPIError.invalidURL }
        var queryItems = components.queryItems ?? []
        queryItems.append(contentsOf: [
            URLQueryItem(name: "action", value: "list"),
            URLQueryItem(name: "deviceId", value: deviceId),
            URLQueryItem(name: "cityId", value: String(cityId))
        ])
        components.queryItems = queryItems
        guard let url = components.url else { throw InfobusAPIError.invalidURL }
        return try await sendAppeal(URLRequest(url: url))
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

    private func get<T: Decodable>(_ url: URL, decoder customDecoder: JSONDecoder? = nil) async throws -> T {
        try await send(URLRequest(url: url), decoder: customDecoder)
    }

    /// Shared by every GET (via the `get` overload above) and every POST
    /// (appeals' `createAppeal`) — validates the HTTP status, then
    /// decodes with whichever decoder the caller needs (`decoder` by
    /// default; `appealsDecoder` for anything with ISO-8601 dates).
    private func send<T: Decodable>(_ request: URLRequest, decoder customDecoder: JSONDecoder? = nil) async throws -> T {
        let (data, response) = try await performRequest(request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw InfobusAPIError.serverError(statusCode: code)
        }
        do {
            return try (customDecoder ?? decoder).decode(T.self, from: data)
        } catch {
            throw InfobusAPIError.decodingFailed(underlying: error)
        }
    }

    /// Shared by `createAppeal`/`fetchAppeals` — same status-code check as
    /// `send`, but checked for an `{"error": ..., "message": ...}` body
    /// FIRST. The Apps Script backend can't set a real HTTP status code
    /// at all (see its own `jsonOutput_` comment), so a rejected request
    /// — bad input, or this device over the anti-spam rate limit — still
    /// comes back as a plain 200 with that shape instead of an
    /// `Appeal`/`[Appeal]`. Checking for it before the real decode turns
    /// what would otherwise be a generic "Неверный формат ответа
    /// сервера" into the actual, useful reason from the server.
    private func sendAppeal<T: Decodable>(_ request: URLRequest) async throws -> T {
        let (data, response) = try await performRequest(request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw InfobusAPIError.serverError(statusCode: code)
        }
        if let serverError = try? appealsDecoder.decode(AppealServerError.self, from: data) {
            throw InfobusAPIError.appealRejected(message: serverError.message ?? serverError.error)
        }
        do {
            return try appealsDecoder.decode(T.self, from: data)
        } catch {
            throw InfobusAPIError.decodingFailed(underlying: error)
        }
    }

    private func performRequest(_ request: URLRequest) async throws -> (Data, URLResponse) {
        do {
            return try await session.data(for: request)
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
