//
//  LocationAuthorizationObserver.swift
//  Infobus
//
//  Tracks the OS-level location permission live, so Settings can tell the
//  difference between "the app's own toggle is off" and "iOS itself denied
//  location" — the app-level toggle has no way to fix the latter, only
//  Settings.app does.
//

import CoreLocation
import Combine

@MainActor
final class LocationAuthorizationObserver: NSObject, ObservableObject {
    @Published private(set) var authorizationStatus: CLAuthorizationStatus

    private let manager: CLLocationManager

    override init() {
        manager = CLLocationManager()
        authorizationStatus = manager.authorizationStatus
        super.init()
        manager.delegate = self
    }

    var isDenied: Bool {
        authorizationStatus == .denied || authorizationStatus == .restricted
    }

    /// Triggers the OS permission prompt if the user has never been asked yet.
    /// Does nothing once already granted or denied — only Settings.app can change that.
    func requestIfNeeded() {
        guard authorizationStatus == .notDetermined else { return }
        manager.requestWhenInUseAuthorization()
    }
}

extension LocationAuthorizationObserver: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            self.authorizationStatus = status
        }
    }
}
