//
//  Bus.swift
//  Infobus
//
//  GET {serviceURL}/cities/{id}/routes/{routeId}/busses
//
//  Every live sample fetched while building this returned an empty array
//  (no vehicles currently reporting), so this shape is transcribed directly
//  from the old Objective-C JSON converter rather than observed firsthand.
//  Decoding is deliberately lenient field-by-field — mirroring the old
//  client's own try/catch around `invalidAdapted` and `filling.percentage` —
//  so one malformed field drops to a safe default instead of losing the
//  whole bus (or the whole array, if a single bad item threw).
//

import Foundation
import CoreLocation

struct Bus: Decodable, Identifiable {
    /// Buses carry no stable server-side id; the device IMEI is the closest thing to one.
    var id: String { imei ?? name }

    let name: String
    let direction: Int?
    let imei: String?
    let lat: Double
    let lon: Double
    let speed: Double?
    let offline: Bool?
    let invalidAdapted: Int
    /// Cabin occupancy, 0–100. Frequently missing/malformed on the wire — defaults to 0.
    let filling: Int

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }

    private enum CodingKeys: String, CodingKey {
        case name, direction, imei, lat, lon, speed, offline, invalidAdapted, filling
    }

    private enum FillingKeys: String, CodingKey {
        case percentage
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = (try? container.decodeIfPresent(String.self, forKey: .name)) ?? ""
        direction = try? container.decodeIfPresent(Int.self, forKey: .direction)
        imei = try? container.decodeIfPresent(String.self, forKey: .imei)
        lat = (try? container.decodeIfPresent(Double.self, forKey: .lat)) ?? 0
        lon = (try? container.decodeIfPresent(Double.self, forKey: .lon)) ?? 0
        speed = try? container.decodeIfPresent(Double.self, forKey: .speed)
        offline = try? container.decodeIfPresent(Bool.self, forKey: .offline)
        invalidAdapted = (try? container.decodeIfPresent(Int.self, forKey: .invalidAdapted)) ?? 0

        if let fillingContainer = try? container.nestedContainer(keyedBy: FillingKeys.self, forKey: .filling) {
            if let percentString = try? fillingContainer.decodeIfPresent(String.self, forKey: .percentage) {
                filling = Int(percentString) ?? 0
            } else {
                filling = (try? fillingContainer.decodeIfPresent(Int.self, forKey: .percentage)) ?? 0
            }
        } else {
            filling = 0
        }
    }
}
