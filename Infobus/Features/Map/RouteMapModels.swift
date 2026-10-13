//
//  RouteMapModels.swift
//  Infobus
//
//  Small models for rendering a route's live buses on a real map — see
//  RouteMapTrack.
//

import Foundation
import CoreLocation

/// A live bus, positioned for display: snapped exactly onto the route's
/// polyline when it's close enough to plausibly belong to it, otherwise
/// shown at its own raw GPS fix so it's visibly off the line rather than
/// silently pulled onto it.
struct MapBusPin: Identifiable {
    let bus: Bus
    let coordinate: CLLocationCoordinate2D
    let isOffRoute: Bool
    /// Compass bearing (0-360°, 0 = north) to rotate the bus icon toward its
    /// actual direction of travel — nil until a second GPS sample exists to
    /// compute it from, or while the bus has barely moved since the last one.
    let bearing: Double?

    var id: String { bus.id }

    static let offRouteThresholdMeters: Double = 80
}
