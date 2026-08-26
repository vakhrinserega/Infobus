//
//  City.swift
//  Infobus
//
//  GET https://infobus.kz/api/countries/{countryId}/cities
//
//  Each city carries its own `serviceURL` — cities can in principle be served
//  by different backends, so every per-city request below is built against
//  the specific city's serviceURL, never a hardcoded host.
//

import Foundation

struct City: Codable, Identifiable, Hashable {
    let id: Int
    let name: String
    let serviceURL: String
}
