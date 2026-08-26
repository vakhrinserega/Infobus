//
//  Station.swift
//  Infobus
//
//  GET {serviceURL}/cities/{id}/stations
//
//  NOTE: coordinates are flat `lat`/`lon` fields on the wire, not a nested
//  location object (verified against a live response) — unlike what the old
//  Objective-C model's separate GeoLocation class might suggest.
//

import Foundation
import CoreLocation

struct Station: Decodable, Identifiable, Hashable {
    let id: Int
    let name: String
    let stationDescription: String?
    let lat: Double
    let lon: Double

    enum CodingKeys: String, CodingKey {
        case id, name, lat, lon
        case stationDescription = "description"
    }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }
}
