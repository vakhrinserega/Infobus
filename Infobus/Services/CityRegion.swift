//
//  CityRegion.swift
//  Infobus
//
//  A single place to answer "what map region frames this city" — used by
//  the Search tab's point picker so it opens already looking at the right
//  city instead of some generic default.
//
//  `cities/{id}` metadata endpoint's own lat/lon is the primary source — a
//  real network call, but small, and exists specifically for "frame the map
//  on this city" (just never wired up anywhere until now). The city's own
//  cached routes/stations is a secondary, offline-friendly fallback — but
//  NOT the primary one: a real captured run showed the raw stations list
//  for one city contains a few entries with bogus `(0, 0)` coordinates,
//  which blew the naive bounding box out to a huge chunk of the globe
//  (latitudeDelta/longitudeDelta in the 80-90° range, centered somewhere off
//  the coast of Africa — exactly the "whole world" view that was reported).
//  Coordinates are filtered before framing, and an implausibly large result
//  is discarded rather than trusted, but `fetchCityInfo` going first avoids
//  this class of bug outright in the common (online) case.
//
//  Shared between SearchView (which resolves this eagerly on city change,
//  so it's usually already on hand by the time a picker sheet opens) and
//  MapPointPickerSheet itself (which resolves it again, independently, if
//  that eager attempt hasn't finished yet by the time it opens — e.g. the
//  user tapped the field right after switching cities). Either caller
//  getting there first is fine; there's no shared mutable state here.
//

import Foundation
import MapKit
import CoreLocation

enum CityRegion {
    /// A city is never going to legitimately span this many degrees in
    /// either direction — anything bigger means the input coordinates were
    /// bad, not that the city is huge.
    private static let maxPlausibleSpanDegrees: CLLocationDegrees = 5

    static func fallback(for city: City, in country: Country) async -> MKCoordinateRegion? {
        if let info = try? await InfobusAPIClient.shared.fetchCityInfo(city) {
            let center = CLLocationCoordinate2D(latitude: info.lat, longitude: info.lon)
            return MKCoordinateRegion(center: center, latitudinalMeters: 10_000, longitudinalMeters: 10_000)
        }

        guard let cached = await CityDataCache.shared.cachedData(for: city, in: country) else {
            return nil
        }
        let validCoordinates = cached.stations
            .map(\.coordinate)
            .filter { CLLocationCoordinate2DIsValid($0) && !($0.latitude == 0 && $0.longitude == 0) }
        guard let region = RouteGeometry.boundingRegion(for: validCoordinates),
              region.span.latitudeDelta < maxPlausibleSpanDegrees,
              region.span.longitudeDelta < maxPlausibleSpanDegrees else {
            return nil
        }
        return region
    }
}
