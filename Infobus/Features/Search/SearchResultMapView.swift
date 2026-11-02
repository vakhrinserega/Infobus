//
//  SearchResultMapView.swift
//  Infobus
//
//  Shows one search result (a `SearchPath`) on a real map, tapped from a row
//  in SearchView: the walking legs to/from the picked points as dashed
//  lines, and each bus leg's route trimmed to just the stretch actually
//  ridden (RouteGeometry.project + .trim) rather than the whole route line
//  — a path with a transfer shows two differently-colored stretches, same
//  idea as the "Карта" tab telling multiple selected routes apart, so
//  RouteMapColor's slots are reused here too.
//
//  Route geometry isn't in `SearchResultItem` — just a route id/number/name
//  — so this screen loads the city's full route list (the same cached data
//  RouteDetailView/RouteReferenceViewModel use) and matches `leg.route.id`
//  against a route. `pathsbwpoints` could plausibly be keyed either by the
//  main routing database's `Route.id` or by the separate live-tracking
//  "busreport" system's `Route.busreportRouteId` (see RouteMapTrack's header
//  for that split) — both are tried, `id` first since this looks like a
//  routing-database endpoint rather than a live-tracking one. If NEITHER
//  matches for some city, that leg falls back to a straight line between
//  its two stops rather than crashing — a visibly straight segment on
//  screen is the tell that it's hitting that fallback.
//
//  Markers: the rider's own picked points (not stops) get a round
//  "walking" glyph — green for departure, red for arrival — so they read
//  as *the rider's* endpoints rather than more bus stops. A transfer stop
//  (the arrival of one leg that's also the departure of the next) gets a
//  single marker, not two overlapping ones, drawn with the same two-arrow
//  swap glyph already used for the "Пересадка" label in SearchView's own
//  result rows. Boarding/alighting stops reuse `StationPinView` — the same
//  neutral stop pin as every other map screen in the app.
//

import SwiftUI
import MapKit

struct SearchResultMapView: View {
    let path: SearchPath
    let fromCoordinate: CLLocationCoordinate2D?
    let toCoordinate: CLLocationCoordinate2D?
    let city: City
    let country: Country

    @State private var cameraPosition: MapCameraPosition = .automatic
    @State private var routesById: [Int: Route] = [:]
    @State private var routesByBusreportId: [Int: Route] = [:]
    @State private var loadState: LoadState<Void> = .idle
    /// Each leg's road-following segment (or straight-line fallback),
    /// computed once in `load()` rather than recomputed from
    /// `RouteGeometry.project`/`.trim` on every SwiftUI body re-evaluation —
    /// indices line up 1:1 with `path.legs`.
    @State private var legSegments: [[CLLocationCoordinate2D]] = []

    var body: some View {
        content
            .navigationTitle("Маршрут на карте")
            .navigationBarTitleDisplayMode(.inline)
            .task {
                await load()
            }
    }

    @ViewBuilder
    private var content: some View {
        switch loadState {
        case .idle, .loading:
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed(let message):
            ContentUnavailableView {
                Label("Не удалось загрузить маршрут", systemImage: "exclamationmark.triangle")
            } description: {
                // `message` is a plain `String` — same `LocalizedStringKey`
                // re-wrap used everywhere else this pattern shows up.
                Text(LocalizedStringKey(message))
            } actions: {
                Button("Повторить") { Task { await load() } }
            }
        case .loaded:
            map
        }
    }

    private var map: some View {
        Map(position: $cameraPosition) {
            if let fromCoordinate, let firstLeg = path.legs.first {
                walkingLine(from: fromCoordinate, to: firstLeg.departureStop.coordinate)
            }

            ForEach(Array(path.legs.enumerated()), id: \.offset) { index, leg in
                let color = RouteMapColor.allCases[index % RouteMapColor.allCases.count].color
                let isLastLeg = index == path.legs.count - 1

                // A darker casing under the colored line, same as the
                // single-route map screen, so it reads against whatever the
                // basemap underneath happens to be.
                let coordinates = legSegments.indices.contains(index) ? legSegments[index] : [leg.departureStop.coordinate, leg.arrivalStop.coordinate]
                MapPolyline(coordinates: coordinates)
                    .stroke(Color.black.opacity(0.25), lineWidth: 6)
                MapPolyline(coordinates: coordinates)
                    .stroke(color, lineWidth: 4)

                // Only the very first boarding point is drawn from
                // `departureStop` — every later leg's departure is the same
                // physical stop as the previous leg's arrival, drawn once
                // below instead of twice (that duplication is exactly what
                // showed up as two overlapping pins at the transfer point).
                if index == 0 {
                    Annotation(leg.departureStop.name, coordinate: leg.departureStop.coordinate, anchor: .bottom) {
                        StationPinView(isCurrent: false)
                    }
                }

                if isLastLeg {
                    Annotation(leg.arrivalStop.name, coordinate: leg.arrivalStop.coordinate, anchor: .bottom) {
                        StationPinView(isCurrent: false)
                    }
                } else {
                    Annotation(leg.arrivalStop.name, coordinate: leg.arrivalStop.coordinate, anchor: .bottom) {
                        RoundGlyphAnnotationView(systemImage: "arrow.triangle.swap", tint: .orange)
                    }
                }
            }

            if let toCoordinate, let lastLeg = path.legs.last {
                walkingLine(from: lastLeg.arrivalStop.coordinate, to: toCoordinate)
            }

            if let fromCoordinate {
                Annotation("Откуда", coordinate: fromCoordinate, anchor: .bottom) {
                    RoundGlyphAnnotationView(systemImage: "figure.walk", tint: .green)
                }
            }
            if let toCoordinate {
                Annotation("Куда", coordinate: toCoordinate, anchor: .bottom) {
                    RoundGlyphAnnotationView(systemImage: "figure.walk", tint: .red)
                }
            }
        }
        .mapControls {
            MapCompass()
            MapScaleView()
            MapUserLocationButton()
        }
    }

    private func walkingLine(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D) -> some MapContent {
        MapPolyline(coordinates: [from, to])
            .stroke(Color.secondary, style: StrokeStyle(lineWidth: 3, lineCap: .round, dash: [1, 8]))
    }

    /// The bit of `leg.route`'s own polyline between its two stops, or —
    /// if the route's geometry couldn't be matched/loaded — a straight line
    /// between them, so the path still reads as continuous. Called once per
    /// leg from `load()` and cached in `legSegments`, not from the view body.
    private func segment(for leg: SearchResultItem) -> [CLLocationCoordinate2D] {
        guard let route = routesById[leg.route.id] ?? routesByBusreportId[leg.route.id] else {
            return [leg.departureStop.coordinate, leg.arrivalStop.coordinate]
        }
        let coordinates = route.coordinates
        guard let start = RouteGeometry.project(leg.departureStop.coordinate, onto: coordinates),
              let end = RouteGeometry.project(leg.arrivalStop.coordinate, onto: coordinates) else {
            return [leg.departureStop.coordinate, leg.arrivalStop.coordinate]
        }
        return RouteGeometry.trim(coordinates, from: start.fraction, to: end.fraction)
    }

    private func load() async {
        loadState = .loading
        do {
            let data = try await CityDataCache.shared.refreshIfNeeded(for: city, in: country)
            routesById = Dictionary(uniqueKeysWithValues: data.routes.map { ($0.id, $0) })
            routesByBusreportId = Dictionary(uniqueKeysWithValues: data.routes.map { ($0.busreportRouteId, $0) })
            legSegments = path.legs.map { segment(for: $0) }
            if let region = RouteGeometry.boundingRegion(for: allCoordinates()) {
                cameraPosition = .region(region)
            }
            loadState = .loaded(())
        } catch {
            // Reuses RoutesListView's existing catalog string rather than a
            // new "...города" variant — same meaning, and it already has
            // translated entries for every supported language.
            loadState = .failed("Не удалось загрузить маршруты")
        }
    }

    private func allCoordinates() -> [CLLocationCoordinate2D] {
        var coordinates: [CLLocationCoordinate2D] = []
        if let fromCoordinate { coordinates.append(fromCoordinate) }
        if let toCoordinate { coordinates.append(toCoordinate) }
        for segment in legSegments {
            coordinates.append(contentsOf: segment)
        }
        return coordinates
    }
}

/// A round colored glyph marker — the rider's own picked points (walking
/// figure, green/red) and a leg transfer (swap arrows, orange) all use this
/// same shape so they read as one family, distinct from the neutral
/// black/white `StationPinView` used for actual boarding/alighting stops.
private struct RoundGlyphAnnotationView: View {
    let systemImage: String
    let tint: Color

    var body: some View {
        ZStack {
            Circle().fill(tint)
            Circle().stroke(Color.white, lineWidth: 2)
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.white)
        }
        .frame(width: 28, height: 28)
        .shadow(radius: 1.5)
    }
}

#Preview {
    NavigationStack {
        SearchResultMapView(
            path: SearchPath(legs: [
                SearchResultItem(
                    departureStop: SearchStopReference(id: 1, name: "Остановка А", location: .init(lat: 53.293, lng: 69.385)),
                    arrivalStop: SearchStopReference(id: 2, name: "Остановка Б", location: .init(lat: 53.282, lng: 69.373)),
                    route: RouteSummary(id: 20, number: "21", name: "мкр.Коктем - ул. Проектируемая"),
                    numStops: 4
                )
            ]),
            fromCoordinate: CLLocationCoordinate2D(latitude: 53.294, longitude: 69.387),
            toCoordinate: CLLocationCoordinate2D(latitude: 53.280, longitude: 69.370),
            city: City(id: 13, name: "Кокшетау", serviceURL: "https://example.com"),
            country: Country(id: 1, code: "kz", name: "Казахстан")
        )
    }
}
