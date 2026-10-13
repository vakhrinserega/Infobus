//
//  RouteGeometry.swift
//  Services
//  Infobus
//
//  Geometry helpers shared by both map screens (single-route detail and the
//  multi-route "Карта" tab): projecting a live bus onto a route's polyline
//  to snap it there (or tell it's too far off to plausibly belong), turning
//  a fraction back into an actual coordinate, computing the bearing between
//  two fixes to point a bus icon the way it's really moving, and framing a
//  map region around one or more routes.
//
//  Uses a flat-plane approximation (longitude scaled by cos(latitude), so
//  degrees behave like a local Cartesian grid) rather than true geodesic
//  segment projection — accurate enough at the scale of a single city bus
//  route (a few km), much simpler than exact spherical geometry.
//

import CoreLocation
import MapKit

enum RouteGeometry {
    /// Real geodesic distance in meters (exact — CLLocation's own great-circle
    /// calculation, not the flat-plane approximation used below).
    static func distance(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> Double {
        CLLocation(latitude: a.latitude, longitude: a.longitude)
            .distance(from: CLLocation(latitude: b.latitude, longitude: b.longitude))
    }

    /// Where `point` falls along `polyline`, as a fraction of its total length
    /// (0 = start, 1 = end), plus the real-world distance from `point` to its
    /// closest spot on the line. Returns nil if the polyline can't be
    /// projected onto (fewer than 2 points, or zero length).
    static func project(
        _ point: CLLocationCoordinate2D,
        onto polyline: [CLLocationCoordinate2D]
    ) -> (fraction: Double, distance: Double)? {
        guard polyline.count >= 2 else { return nil }

        let originLat = polyline[0].latitude
        let lonScale = cos(originLat * .pi / 180)
        func flat(_ c: CLLocationCoordinate2D) -> (x: Double, y: Double) {
            (x: c.longitude * lonScale, y: c.latitude)
        }

        let cumulativeLength = cumulativeLengths(of: polyline)
        let totalLength = cumulativeLength.last ?? 0
        guard totalLength > 0 else { return nil }

        let p = flat(point)
        var bestFraction = 0.0
        var bestFlatDistanceSquared = Double.greatestFiniteMagnitude

        for i in 0..<(polyline.count - 1) {
            let a = flat(polyline[i])
            let b = flat(polyline[i + 1])
            let dx = b.x - a.x
            let dy = b.y - a.y
            let segmentLengthSquared = dx * dx + dy * dy

            let t: Double
            if segmentLengthSquared > 0 {
                t = max(0, min(1, ((p.x - a.x) * dx + (p.y - a.y) * dy) / segmentLengthSquared))
            } else {
                t = 0
            }

            let closestX = a.x + t * dx
            let closestY = a.y + t * dy
            let flatDistanceSquared = (p.x - closestX) * (p.x - closestX) + (p.y - closestY) * (p.y - closestY)

            if flatDistanceSquared < bestFlatDistanceSquared {
                bestFlatDistanceSquared = flatDistanceSquared
                let segmentLength = distance(polyline[i], polyline[i + 1])
                let arcLength = cumulativeLength[i] + t * segmentLength
                bestFraction = arcLength / totalLength
            }
        }

        // Both flat axes are scaled to be degree-equivalent, so this converts
        // back to real meters using an approximate meters-per-degree constant
        // rather than a second geodesic pass.
        let metersPerDegree = 111_320.0
        let realDistance = sqrt(bestFlatDistanceSquared) * metersPerDegree

        return (fraction: bestFraction, distance: realDistance)
    }

    /// The inverse of `project(_:onto:)`'s fraction — the actual coordinate
    /// at a given fraction (0...1) along `polyline`. Used to snap a live bus
    /// exactly onto the line once its fraction is known, so it's drawn
    /// sitting on the route rather than at its (slightly noisy) raw GPS fix.
    static func coordinate(atFraction fraction: Double, along polyline: [CLLocationCoordinate2D]) -> CLLocationCoordinate2D? {
        guard polyline.count >= 2 else { return nil }
        let cumulativeLength = cumulativeLengths(of: polyline)
        let totalLength = cumulativeLength.last ?? 0
        guard totalLength > 0 else { return nil }

        let targetLength = max(0, min(1, fraction)) * totalLength

        for i in 0..<(polyline.count - 1) {
            let segmentStart = cumulativeLength[i]
            let segmentEnd = cumulativeLength[i + 1]
            guard targetLength <= segmentEnd || i == polyline.count - 2 else { continue }
            let segmentLength = segmentEnd - segmentStart
            let t = segmentLength > 0 ? (targetLength - segmentStart) / segmentLength : 0
            let a = polyline[i]
            let b = polyline[i + 1]
            return CLLocationCoordinate2D(
                latitude: a.latitude + (b.latitude - a.latitude) * t,
                longitude: a.longitude + (b.longitude - a.longitude) * t
            )
        }
        return polyline.last
    }

    /// Compass bearing (0-360°, 0 = north, clockwise) from `from` to `to` —
    /// used to rotate a live bus's icon to face the direction it's actually
    /// moving, computed from its own last two GPS fixes rather than trusting
    /// Bus.direction (see RouteMapTrack's header for why).
    static func bearing(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D) -> Double {
        let lat1 = from.latitude * .pi / 180
        let lat2 = to.latitude * .pi / 180
        let deltaLon = (to.longitude - from.longitude) * .pi / 180
        let y = sin(deltaLon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(deltaLon)
        let bearingDegrees = atan2(y, x) * 180 / .pi
        return (bearingDegrees + 360).truncatingRemainder(dividingBy: 360)
    }

    /// A map region tightly framing every coordinate given, with a small
    /// padding factor so points near the edge aren't flush against the
    /// screen border. Pass the union of every currently-shown route's
    /// coordinates to frame all of them at once. Returns nil for an empty
    /// input.
    static func boundingRegion(for coordinates: [CLLocationCoordinate2D], paddingFactor: Double = 1.3) -> MKCoordinateRegion? {
        guard !coordinates.isEmpty else { return nil }
        let lats = coordinates.map(\.latitude)
        let lons = coordinates.map(\.longitude)
        guard let minLat = lats.min(), let maxLat = lats.max(),
              let minLon = lons.min(), let maxLon = lons.max() else { return nil }
        let center = CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2, longitude: (minLon + maxLon) / 2)
        let span = MKCoordinateSpan(
            latitudeDelta: max((maxLat - minLat) * paddingFactor, 0.01),
            longitudeDelta: max((maxLon - minLon) * paddingFactor, 0.01)
        )
        return MKCoordinateRegion(center: center, span: span)
    }

    private static func cumulativeLengths(of polyline: [CLLocationCoordinate2D]) -> [Double] {
        var lengths: [Double] = [0]
        for i in 1..<polyline.count {
            lengths.append(lengths[i - 1] + distance(polyline[i - 1], polyline[i]))
        }
        return lengths
    }
}
