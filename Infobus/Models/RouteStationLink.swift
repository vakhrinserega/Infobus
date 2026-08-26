//
//  RouteStationLink.swift
//  Infobus
//
//  GET {serviceURL}/cities/{id}/routestations
//
//  Each route has TWO independent, separately-sequenced station orderings —
//  one per `directionForward` value — not one list that can be reversed to
//  get the other direction. The old Objective-C client folded both into a
//  single signed sequenceNumber (negative = backward); we keep the two
//  fields separate here and let the feature layer group by directionForward.
//

import Foundation

struct RouteStationLink: Decodable {
    let routeId: Int
    let stationId: Int
    let sequenceNumber: Int
    let directionForward: Bool

    enum CodingKeys: String, CodingKey {
        case routeId, stationId, sequenceNumber, directionForward
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        routeId = try container.decode(Int.self, forKey: .routeId)
        stationId = try container.decode(Int.self, forKey: .stationId)
        sequenceNumber = try container.decode(Int.self, forKey: .sequenceNumber)
        // The old app treated a missing flag as "forward" — kept for parity.
        directionForward = try container.decodeIfPresent(Bool.self, forKey: .directionForward) ?? true
    }
}
