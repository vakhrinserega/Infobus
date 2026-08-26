//
//  AppSettingsStore.swift
//  Infobus
//
//  User-facing preferences that live in the Settings screen but are read by
//  other features (Map, mnemoscheme). Backed by UserDefaults directly rather
//  than @AppStorage inside the views themselves, since these flags are
//  consumed well outside Settings and want one shared, observable source of
//  truth injected via the environment.
//

import Foundation
import Combine

@MainActor
final class AppSettingsStore: ObservableObject {
    private enum Keys {
        static let highlightAccessibleBuses = "settings.highlightAccessibleBuses"
        static let filterAccessibleBusesOnly = "settings.filterAccessibleBusesOnly"
        static let useMyLocation = "settings.useMyLocation"
    }

    private let defaults: UserDefaults

    /// Marks wheelchair/adapted buses with a distinct badge wherever buses are
    /// shown. On by default — this makes them visible, it doesn't restrict anything.
    @Published var highlightAccessibleBuses: Bool {
        didSet { defaults.set(highlightAccessibleBuses, forKey: Keys.highlightAccessibleBuses) }
    }

    /// Hides non-adapted buses on Map/mnemoscheme entirely. Off by default —
    /// a situational filter, independent of the always-available highlight above.
    @Published var filterAccessibleBusesOnly: Bool {
        didSet { defaults.set(filterAccessibleBusesOnly, forKey: Keys.filterAccessibleBusesOnly) }
    }

    /// Governs whether the app uses the device's location to show "you are here"
    /// on the Map and to highlight the current station on a route's mnemoscheme —
    /// independent of the OS-level location permission itself.
    @Published var useMyLocation: Bool {
        didSet { defaults.set(useMyLocation, forKey: Keys.useMyLocation) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.highlightAccessibleBuses = defaults.object(forKey: Keys.highlightAccessibleBuses) as? Bool ?? true
        self.filterAccessibleBusesOnly = defaults.object(forKey: Keys.filterAccessibleBusesOnly) as? Bool ?? false
        self.useMyLocation = defaults.object(forKey: Keys.useMyLocation) as? Bool ?? true
    }
}
