//
//  CityInfo.swift
//  Infobus
//
//  GET {serviceURL}/api/cities/{id}
//  City-level metadata: map framing and an optional city-wide announcement.
//

import Foundation

struct CityInfo: Decodable {
    let id: Int
    let name: String
    let lat: Double
    let lon: Double
    let mapZoom: Int
    let mapLayers: [String]
    let message: String
    let displayMessage: Bool
}
