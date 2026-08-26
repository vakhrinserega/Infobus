//
//  RouteStop.swift
//  Infobus
//
//  Small models specific to the mnemoscheme screen.
//

import Foundation

/// One station as shown on the mnemoscheme, in the currently displayed
/// direction's order.
struct RouteStop: Identifiable, Hashable {
    let station: Station
    let sequenceNumber: Int
    /// This station's position along the route's physical polyline, 0...1 —
    /// direction-independent (it's the same physical stop either way), used
    /// to figure out which two stops bracket a given live bus.
    let fraction: Double

    var id: Int { station.id }
}

/// A live bus already projected onto the route's polyline.
struct PositionedBus: Identifiable {
    let bus: Bus
    let fraction: Double
    /// True when the bus's real GPS position is too far from the route line
    /// to plausibly belong to it — shown at its nearest point but marked as
    /// uncertain, rather than silently snapped as if the position were solid.
    let isOffRoute: Bool

    var id: String { bus.id }

    static let offRouteThresholdMeters: Double = 80
}

/// Where a positioned bus lands between two adjacent stops in the CURRENTLY
/// DISPLAYED direction's order — `t` is 0...1 between `beforeIndex` and
/// `beforeIndex + 1`. Recomputed whenever the direction (display order)
/// changes, even though the bus's own `fraction` doesn't.
struct PlacedBus: Identifiable {
    let bus: Bus
    let isOffRoute: Bool
    let beforeIndex: Int
    let t: Double

    var id: String { bus.id }
}
