//
//  Bus.swift
//  Infobus
//
//  GET {serviceURL}/cities/{id}/routes/{routeId}/busses
//
//  Decoding is deliberately lenient field-by-field — mirroring the old
//  client's own try/catch around `invalidAdapted` and `filling.percentage` —
//  so one malformed field drops to a safe default instead of losing the
//  whole bus (or the whole array, if a single bad item threw).
//
//  `direction`: confirmed against real live data (once buses were actually
//  running) to be the bus's actual compass heading, safe to use directly for
//  rotating its icon — no need to infer it from successive GPS fixes.
//

import Foundation
import CoreLocation

struct Bus: Decodable, Identifiable {
    /// Buses carry no stable server-side id; the device IMEI is the closest
    /// thing to one. Falls back further to a coordinate string (not just
    /// `name`, which decodes to "" when missing) so two buses that are both
    /// missing imei AND name don't collide onto the same id in SwiftUI lists.
    var id: String {
        if let imei, !imei.isEmpty { return imei }
        if !name.isEmpty { return name }
        return "\(lat),\(lon)"
    }

    let name: String
    /// Compass heading, 0–360°, 0 = north — used directly to rotate the bus
    /// icon toward its real direction of travel.
    let direction: Int?
    let imei: String?
    let lat: Double
    let lon: Double
    let speed: Double?
    let offline: Bool?
    let invalidAdapted: Int
    /// Cabin occupancy, 0–100 — nil when the field is missing/unparseable on
    /// the wire (frequent), as distinct from an explicit 0%. Callers should
    /// treat nil as "no data" rather than "empty".
    let filling: Int?

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
        // Same string-or-number inconsistency as `filling.percentage`
        // below — some backends send this as a numeric string rather
        // than a bare number. A plain `decodeIfPresent(Int.self, ...)`
        // would throw on a string value, and the surrounding `try?`
        // would silently swallow that into `nil` — meaning every bus
        // from such a backend would decode fine but with NO direction at
        // all, with nothing in the logs to say why. Try the string form
        // first, same pattern as `filling`.
        if let directionString = try? container.decodeIfPresent(String.self, forKey: .direction), let value = Int(directionString) {
            direction = value
        } else if let value = try? container.decodeIfPresent(Int.self, forKey: .direction) {
            direction = value
        } else {
            direction = nil
        }
        imei = try? container.decodeIfPresent(String.self, forKey: .imei)
        lat = (try? container.decodeIfPresent(Double.self, forKey: .lat)) ?? 0
        lon = (try? container.decodeIfPresent(Double.self, forKey: .lon)) ?? 0
        speed = try? container.decodeIfPresent(Double.self, forKey: .speed)
        offline = try? container.decodeIfPresent(Bool.self, forKey: .offline)
        invalidAdapted = (try? container.decodeIfPresent(Int.self, forKey: .invalidAdapted)) ?? 0

        if let fillingContainer = try? container.nestedContainer(keyedBy: FillingKeys.self, forKey: .filling) {
            if let percentString = try? fillingContainer.decodeIfPresent(String.self, forKey: .percentage), let value = Int(percentString) {
                filling = value
            } else if let value = try? fillingContainer.decodeIfPresent(Int.self, forKey: .percentage) {
                filling = value
            } else {
                filling = nil
            }
        } else {
            filling = nil
        }
    }
}
