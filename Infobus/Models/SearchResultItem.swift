//
//  SearchResultItem.swift
//  Infobus
//
//  GET {serviceURL}/cities/{id}/pathsbwpoints?sourceLat=&sourceLng=&targetLat=&targetLng=
//
//  This endpoint alone uses snake_case keys and a trimmed-down inline route
//  shape — inconsistent with every other endpoint, but that's what the old
//  client's converter reads, so it's kept exactly as-is here.
//
//  The response is an array of PATHS, each an array of 1+ LEGS — a direct
//  connection is a single-leg path, a connection requiring a transfer is a
//  path with two (or more) legs chained departure→arrival→departure→arrival.
//  Confirmed against a real response captured via the decode-failure logging
//  in InfobusAPIClient: decoding this as a flat `[SearchResultItem]` (what
//  this file used to do) always failed, because the real shape is
//  `[[SearchResultItem]]`. This also matches what the old Objective-C app's
//  own (if internally inconsistent) typing hinted at — its completion block
//  was declared `NSArray<NSArray<SearchResultItem *> *> *`, and
//  `processSearchResults:` genuinely iterated an inner array per path.
//

import Foundation
import CoreLocation

/// A stop as embedded in a `pathsbwpoints` response — a distinct, smaller
/// shape from `Station` (the `/stations` list endpoint): coordinates sit
/// under a nested `location` object with `lat`/`lng` here, vs. flat
/// `lat`/`lon` fields there, and there's no `description`. Also confirmed
/// against a real captured response.
struct SearchStopReference: Decodable, Identifiable, Hashable {
    let id: Int
    let name: String
    let location: Coordinate

    struct Coordinate: Decodable, Hashable {
        let lat: Double
        let lng: Double
    }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: location.lat, longitude: location.lng)
    }
}

/// One leg of a path: board `route` at `departureStop`, ride `numStops`
/// stops, get off at `arrivalStop`.
struct SearchResultItem: Decodable, Identifiable {
    var id: String { "\(departureStop.id)-\(arrivalStop.id)-\(route.id)" }

    let departureStop: SearchStopReference
    let arrivalStop: SearchStopReference
    let route: RouteSummary
    let numStops: Int

    enum CodingKeys: String, CodingKey {
        case departureStop = "departure_stop"
        case arrivalStop = "arrival_stop"
        case route
        case numStops = "num_stops"
    }
}

/// A trimmed route reference inlined by the search endpoint — distinct from
/// `Route` (a different endpoint, with different field names: routeNumber
/// vs. number, routeName vs. name).
struct RouteSummary: Decodable, Identifiable {
    let id: Int
    let number: String
    let name: String
}

/// One complete way to get from the picked departure point to the picked
/// destination point — one leg if direct, more than one if it requires a
/// transfer. `pathsbwpoints` returns an array of these.
struct SearchPath: Identifiable {
    let legs: [SearchResultItem]

    var id: String { legs.map(\.id).joined(separator: "|") }
}
