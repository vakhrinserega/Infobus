//
//  SelectedCityStore.swift
//  Infobus
//
//  Persists the user's chosen country/city across launches. Settings is the
//  only screen that writes to this; every other feature just reads it to know
//  which city's data to show. A JSON blob in UserDefaults, not a separate
//  file — this is two small structs, not worth its own cache entry.
//

import Foundation
import Combine

@MainActor
final class SelectedCityStore: ObservableObject {
    private enum Keys {
        static let country = "settings.selectedCountry"
        static let city = "settings.selectedCity"
    }

    private let defaults: UserDefaults

    @Published private(set) var selectedCountry: Country?
    @Published private(set) var selectedCity: City?

    var hasSelection: Bool { selectedCity != nil }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.selectedCountry = Self.load(Country.self, key: Keys.country, from: defaults)
        self.selectedCity = Self.load(City.self, key: Keys.city, from: defaults)
    }

    /// Persists the new selection and returns whether the city actually changed
    /// (vs. re-picking the same one), so callers know whether a data refresh is needed.
    @discardableResult
    func select(country: Country, city: City) -> Bool {
        // Compare BOTH ids, not just the city's: cities are scoped per-country
        // by the API, so a city id alone isn't guaranteed unique across countries.
        let changed = selectedCity?.id != city.id || selectedCountry?.id != country.id
        selectedCountry = country
        selectedCity = city
        Self.save(country, key: Keys.country, to: defaults)
        Self.save(city, key: Keys.city, to: defaults)
        return changed
    }

    private static func load<T: Decodable>(_ type: T.Type, key: String, from defaults: UserDefaults) -> T? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    private static func save<T: Encodable>(_ value: T, key: String, to defaults: UserDefaults) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        defaults.set(data, forKey: key)
    }
}
