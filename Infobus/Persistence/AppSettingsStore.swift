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
        static let useMyLocation = "settings.useMyLocation"
    }

    private let defaults: UserDefaults

    /// Marks ramp-equipped buses with a distinct badge wherever buses are shown.
    /// All buses always show — this only adds a badge, it never hides anything.
    /// On by default.
    @Published var highlightAccessibleBuses: Bool {
        didSet { defaults.set(highlightAccessibleBuses, forKey: Keys.highlightAccessibleBuses) }
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
        self.useMyLocation = defaults.object(forKey: Keys.useMyLocation) as? Bool ?? true
    }
}
