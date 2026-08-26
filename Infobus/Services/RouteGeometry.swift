//
//  RouteGeometry.swift
//  Services
//  Infobus
//
//  Projecting a point onto a route's polyline — used here to place a live
//  bus between the two stations closest to it along the schematic, and
//  meant to be reused by the Map screen later for the same GPS-snapping
//  idea (a bus rendered on its nearest point on the line, unless it's too
//  far off to plausibly belong to the route, per the earlier design
//  discussion).
//
//  Uses a flat-plane approximation (longitude scaled by cos(latitude), so
//  degrees behave like a local Cartesian grid) rather than true geodesic
//  segment projection — accurate enough at the scale of a single city bus
//  route (a few km), much simpler than exact spherical geometry.
//

import CoreLocation

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

        var cumulativeLength: [Double] = [0]
        for i in 1..<polyline.count {
            cumulativeLength.append(cumulativeLength[i - 1] + distance(polyline[i - 1], polyline[i]))
        }
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
}
