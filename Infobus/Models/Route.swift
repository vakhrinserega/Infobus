//
//  Route.swift
//  Infobus
//
//  GET {serviceURL}/cities/{id}/routes
//

import Foundation
import CoreLocation

struct Route: Decodable, Identifiable, Hashable {
    let id: Int
    let cityId: Int
    let busreportRouteId: Int
    let routeName: String
    let routeNumber: String

    /// Raw polyline as returned by the API: comma-separated "lon lat" pairs,
    /// e.g. "71.396123 51.157048, 71.396522 51.159953, ...". Longitude comes
    /// first in each pair — confirmed against real Astana coordinates (71°E, 51°N).
    let location: String

    /// The route's shape, parsed from `location` on access.
    var coordinates: [CLLocationCoordinate2D] {
        location
            .split(separator: ",")
            .compactMap { pair in
                let parts = pair.trimmingCharacters(in: .whitespaces).split(separator: " ")
                guard parts.count == 2,
                      let lon = Double(parts[0]),
                      let lat = Double(parts[1]) else { return nil }
                return CLLocationCoordinate2D(latitude: lat, longitude: lon)
            }
    }

    /// Matches the old app's "12 АО «ГазМаш» — пос. «Кирпичный»" style label.
    var numberWithName: String {
        "\(routeNumber) \(routeName)"
    }
}
