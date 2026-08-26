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

import Foundation

struct SearchResultItem: Decodable, Identifiable {
    var id: String { "\(departureStop.id)-\(arrivalStop.id)-\(route.id)" }

    let departureStop: Station
    let arrivalStop: Station
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
