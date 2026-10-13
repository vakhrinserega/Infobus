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
//  start() actively asks for permission itself (when never asked before)
//  instead of only working if Settings already triggered the prompt. The
//  map tab is the app's first screen now, so a rider tapping the map's own
//  "locate me" button/blue dot needs this to work on its own — waiting for
//  a visit to Settings first would leave that button silently doing
//  nothing on a fresh install.
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

    func start() {
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            manager.startUpdatingLocation()
        case .notDetermined:
            // startUpdatingLocation() happens once the delegate reports the
            // outcome, below — the user may take a moment to answer the
            // system prompt.
            manager.requestWhenInUseAuthorization()
        case .denied, .restricted:
            break
        @unknown default:
            break
        }
    }

    func stop() {
        manager.stopUpdatingLocation()
    }
}

extension UserLocationProvider: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            guard status == .authorizedWhenInUse || status == .authorizedAlways else { return }
            manager.startUpdatingLocation()
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let coordinate = locations.last?.coordinate else { return }
        Task { @MainActor in
            self.currentCoordinate = coordinate
        }
    }
}
