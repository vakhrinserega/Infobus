//
//  Country.swift
//  Infobus
//
//  GET https://infobus.kz/api/countries
//

import Foundation

struct Country: Decodable, Identifiable, Hashable {
    let id: Int
    let code: String
    let name: String
}
