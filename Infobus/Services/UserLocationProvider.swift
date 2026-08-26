//
//  UserLocationProvider.swift
//  Infobus
//
//  Live user location, separate from LocationAuthorizationObserver (which
//  only tracks permission *status* for Settings' UI). Instantiated per
//  screen that needs it and started/stopped with that screen's lifecycle
//  (start on appear, stop on disappear) rather than kept as an app-wide
//  singleton, so nothing polls GPS while no relevant screen is open.
//

import CoreLocation
import Combine

@MainActor
final class UserLocationProvider: NSObject, ObservableObject {
    @Published private(set) var currentCoordinate: CLLocationCoordinate2D?

    private let manager: CLLocationManager

    override init() {
        manager = CLLocationManager()
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
    }

    /// No-ops if the OS permission isn't already granted — this provider
    /// doesn't prompt; Settings' own location toggle handles that.
    func start() {
        let status = manager.authorizationStatus
        guard status == .authorizedWhenInUse || status == .authorizedAlways else { return }
        manager.startUpdatingLocation()
    }

    func stop() {
        manager.stopUpdatingLocation()
    }
}

extension UserLocationProvider: CLLocationManagerDelegate {
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let coordinate = locations.last?.coordinate else { return }
        Task { @MainActor in
            self.currentCoordinate = coordinate
        }
    }
}
