//
//  Prediction.swift
//  Infobus
//
//  GET {serviceURL}/cities/{id}/stations/{stationId}/prediction
//
//  No live (non-empty) response was available while building this, and the
//  old client passed the value through unmodified as a number without
//  documenting its unit. Decoded as Double so an unexpected fractional value
//  won't fail decoding; confirm the real unit (minutes? seconds?) against a
//  live response before trusting it in UI copy.
//

import Foundation

struct Prediction: Decodable, Identifiable {
    var id: Int { routeId }
    let routeId: Int
    let prediction: Double
}
