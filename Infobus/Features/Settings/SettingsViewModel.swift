//
//  SettingsViewModel.swift
//  Infobus
//
//  Drives the city picker (countries, then cities for the chosen country) and
//  kicks off a background city-data refresh the moment a new city is picked —
//  "refresh on selection", not on a timer.
//

import Foundation
import Combine

@MainActor
final class SettingsViewModel: ObservableObject {
    enum LoadState<Value> {
        case idle
        case loading
        case loaded(Value)
        case failed(String)
    }

    @Published var countriesState: LoadState<[Country]> = .idle
    @Published var citiesState: LoadState<[City]> = .idle

    /// True while a just-picked city's routes/stations/links are being fetched,
    /// so the picker can show that something is happening instead of the
    /// refresh running silently off-screen.
    @Published var isRefreshingCityData = false

    /// Set when a background refresh fails, so Settings can surface it instead
    /// of leaving the user with a persisted city selection and silently stale
    /// (or entirely missing) route/station data.
    @Published var cityDataRefreshError: String?

    private let apiClient: InfobusAPIClient
    private let cache: CityDataCache

    /// Guards against a slow response for a country the user has already
    /// navigated away from landing after a later request and clobbering it.
    private var citiesRequestToken = UUID()

    private var pendingRefreshCity: City?
    private var pendingRefreshCountry: Country?

    init(apiClient: InfobusAPIClient = .shared, cache: CityDataCache = .shared) {
        self.apiClient = apiClient
        self.cache = cache
    }

    func loadCountries() async {
        countriesState = .loading
        do {
            let countries = try await apiClient.fetchCountries()
            countriesState = .loaded(countries)
        } catch {
            countriesState = .failed("Не удалось загрузить список стран")
        }
    }

    func loadCities(for country: Country) async {
        let token = UUID()
        citiesRequestToken = token
        citiesState = .loading
        do {
            let cities = try await apiClient.fetchCities(countryId: country.id)
            guard citiesRequestToken == token else { return }
            citiesState = .loaded(cities)
        } catch {
            guard citiesRequestToken == token else { return }
            citiesState = .failed("Не удалось загрузить список городов")
        }
    }

    /// Persists the selection via `store`, then — only if the city actually
    /// changed — force-refreshes that city's routes/stations/links so the rest
    /// of the app has current data as soon as the user gets there.
    func selectCity(_ city: City, country: Country, store: SelectedCityStore) {
        let changed = store.select(country: country, city: city)
        guard changed else { return }
        refreshCityData(city: city, country: country)
    }

    /// Re-attempts the most recent refresh after a failure — the retry
    /// affordance surfaced next to `cityDataRefreshError` in Settings.
    func retryCityDataRefresh() {
        guard let city = pendingRefreshCity, let country = pendingRefreshCountry else { return }
        refreshCityData(city: city, country: country)
    }

    private func refreshCityData(city: City, country: Country) {
        pendingRefreshCity = city
        pendingRefreshCountry = country
        cityDataRefreshError = nil
        isRefreshingCityData = true
        Task {
            defer { isRefreshingCityData = false }
            do {
                _ = try await cache.forceRefresh(for: city, in: country)
            } catch {
                cityDataRefreshError = "Не удалось обновить маршруты и остановки для этого города"
            }
        }
    }
}
