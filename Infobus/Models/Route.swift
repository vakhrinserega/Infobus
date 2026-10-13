//
//  Route.swift
//  Infobus
//
//  GET {serviceURL}/cities/{id}/routes
//
//  `schedule` is real but per-city, not universal: confirmed live against
//  Kokshetau (cityId 13), where every route carries a populated schedule —
//  but against Astana (cityId 1), where the key is present on every route
//  yet always `null`. Whether it's filled in depends entirely on whether
//  that city's operator entered timetable data on their end, so this is
//  optional and every screen that reads it must handle it being absent.
//

import Foundation
import CoreLocation

struct Route: Codable, Identifiable, Hashable {
    let id: Int
    let cityId: Int
    let busreportRouteId: Int
    let routeName: String
    let routeNumber: String

    /// Raw polyline as returned by the API: comma-separated "lon lat" pairs,
    /// e.g. "71.396123 51.157048, 71.396522 51.159953, ...". Longitude comes
    /// first in each pair — confirmed against real Astana coordinates (71°E, 51°N).
    let location: String

    /// Interval/first-last-departure timetable — nil for most cities today
    /// (see header). When present, it describes the route as a whole, not
    /// per direction: the API doesn't split it by directionForward the way
    /// RouteStationLink does.
    let schedule: RouteSchedule?

    /// A stored property's own `= nil` only removes it from the *synthesized*
    /// memberwise init entirely (rather than making it a defaulted
    /// parameter, which is what actually broke every existing call site
    /// last round) — so `schedule` gets a real default the correct way,
    /// through this explicit init, which Codable's own synthesized
    /// `init(from:)`/`encode(to:)` are unaffected by since neither is
    /// written here by hand.
    init(
        id: Int,
        cityId: Int,
        busreportRouteId: Int,
        routeName: String,
        routeNumber: String,
        location: String,
        schedule: RouteSchedule? = nil
    ) {
        self.id = id
        self.cityId = cityId
        self.busreportRouteId = busreportRouteId
        self.routeName = routeName
        self.routeNumber = routeNumber
        self.location = location
        self.schedule = schedule
    }

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

struct RouteSchedule: Codable, Hashable {
    /// Planned fleet size for this route — distinct from however many buses
    /// happen to be broadcasting live right now.
    let busCount: Int
    /// Minutes between buses.
    let interval: Int
    let startStation: RouteScheduleStation
    let endStation: RouteScheduleStation
}

struct RouteScheduleStation: Codable, Hashable {
    let stationName: String
    /// Wire format "HH:mm" (24h), e.g. "06:53" — kept as a plain string
    /// rather than parsed to Date, since it's only ever displayed as-is and
    /// isn't tied to any particular calendar day.
    let firstTime: String
    let lastTime: String
}
