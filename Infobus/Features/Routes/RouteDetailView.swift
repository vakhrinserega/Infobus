//
//  RouteDetailView.swift
//  Infobus
//
//  A single route's live map: its line, station pins, and buses snapped
//  onto the line (or left at their raw GPS fix when too far off). Station
//  pins only show once zoomed in close enough, and bus icons shrink at a
//  distance — both driven by the map's live camera distance — so a
//  zoomed-out view isn't cluttered with pins nobody can usefully tap yet.
//

import SwiftUI
import MapKit

struct RouteDetailView: View {
    let route: Route
    let city: City
    let country: Country

    @EnvironmentObject private var settings: AppSettingsStore
    @StateObject private var track: RouteMapTrack
    @StateObject private var locationProvider = UserLocationProvider()
    @State private var cameraPosition: MapCameraPosition = .automatic
    @State private var cameraDistance: Double = 3000
    @State private var currentCamera: MapCamera?
    /// Fallback center for `zoom(by:)` — see the identical property in
    /// MapView.swift for why this exists (the same hard `guard let
    /// currentCamera` bug was here too, just not the one reported).
    @State private var lastKnownCenter: CLLocationCoordinate2D?

    /// Station pins only render once the camera is closer than this (meters).
    /// Kept generous on purpose — stations should show up while still fairly
    /// zoomed out rather than only after zooming in a lot.
    private let stationVisibleMaxDistance: Double = 8000

    /// Below this camera distance, station pins step up to their larger
    /// size — "close" zoom, as opposed to the "medium" zoom range between
    /// this and `stationVisibleMaxDistance`, where they stay at their
    /// normal size.
    private let stationCloseZoomDistance: Double = 2000

    init(route: Route, city: City, country: Country) {
        self.route = route
        self.city = city
        self.country = country
        _track = StateObject(wrappedValue: RouteMapTrack(route: route, city: city, country: country))
    }

    var body: some View {
        content
            .navigationTitle(route.routeNumber)
            .navigationBarTitleDisplayMode(.inline)
            .task {
                if let region = RouteGeometry.boundingRegion(for: route.coordinates) {
                    cameraPosition = .region(region)
                    lastKnownCenter = region.center
                }
                await track.loadStops()
            }
            .onAppear {
                track.startPolling()
                if settings.useMyLocation { locationProvider.start() }
            }
            .onDisappear {
                track.stopPolling()
                locationProvider.stop()
            }
            .onReceive(locationProvider.$currentCoordinate) { coordinate in
                if let coordinate {
                    track.updateCurrentStation(from: coordinate)
                }
            }
    }

    @ViewBuilder
    private var content: some View {
        switch track.stopsState {
        case .idle, .loading:
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed(let message):
            ContentUnavailableView {
                Label("Не удалось загрузить остановки", systemImage: "exclamationmark.triangle")
            } description: {
                // `message` is a plain `String` from RouteMapTrack —
                // `Text(String)` never looks it up in Localizable.xcstrings.
                Text(LocalizedStringKey(message))
            } actions: {
                Button("Повторить") { Task { await track.loadStops() } }
            }
        case .loaded(let stations):
            if stations.isEmpty {
                ContentUnavailableView("Остановки не найдены", systemImage: "mappin.slash")
            } else {
                map(stations: stations)
            }
        }
    }

    /// Stations and buses are added to the map in two separate passes
    /// (not interleaved) so every bus annotation is declared after every
    /// station annotation — buses are meant to always sit on top, since a
    /// bus that happens to be sitting right at a stop should never be
    /// hidden behind that stop's pin.
    private func map(stations: [Station]) -> some View {
        Map(position: $cameraPosition) {
            // A darker casing under the colored line keeps the route legible
            // against whatever the map's own basemap colors happen to be
            // underneath it (roads, parks, water), the same way transit maps
            // give their lines a light outline.
            MapPolyline(coordinates: route.coordinates)
                .stroke(Color.black.opacity(0.25), lineWidth: 6)
            MapPolyline(coordinates: route.coordinates)
                .stroke(Color.accentColor, lineWidth: 4)

            if cameraDistance < stationVisibleMaxDistance {
                ForEach(stations) { station in
                    Annotation(station.name, coordinate: station.coordinate, anchor: .bottom) {
                        StationAnnotationView(
                            station: station,
                            isCurrent: station.id == track.currentStationId,
                            fetch: { await track.fetchPredictions(stationId: station.id) },
                            // This screen only ever draws its own single route, so
                            // there's no SelectedRoutesStore to consult — a
                            // prediction row for THIS route gets the same accent
                            // color as the line on screen, everything else falls
                            // back to StationPredictionSheet's own neutral gray.
                            colorForRoute: { routeId in routeId == route.busreportRouteId ? Color.accentColor : nil }
                        )
                        .scaleEffect(stationScale)
                        .zIndex(0)
                    }
                }
            }

            ForEach(track.buses) { busPin in
                Annotation("", coordinate: busPin.coordinate, anchor: .center) {
                    BusAnnotationView(
                        bus: busPin.bus,
                        isOffRoute: busPin.isOffRoute,
                        bearing: busPin.bearing,
                        routeColor: .accentColor,
                        occupancyPercent: busPin.bus.filling
                    )
                    .scaleEffect(busScale)
                    .zIndex(1)
                }
            }

            UserAnnotation()
        }
        .mapControls {
            MapCompass()
            MapScaleView()
            MapUserLocationButton()
        }
        .onMapCameraChange(frequency: .continuous) { context in
            cameraDistance = context.camera.distance
            currentCamera = context.camera
        }
        .overlay(alignment: .bottomTrailing) {
            zoomControls
        }
    }

    /// Smaller the farther out the camera is — roughly full-size within
    /// ~800m, shrinking down to about 65% by 6km out.
    private var busScale: CGFloat {
        let minDistance = 800.0
        let maxDistance = 6000.0
        let clamped = min(max(cameraDistance, minDistance), maxDistance)
        let t = (clamped - minDistance) / (maxDistance - minDistance)
        return 1.0 - 0.35 * CGFloat(t)
    }

    /// 1.0 through "medium" zoom (their current, unchanged size), stepping
    /// up to 1.4 once the camera is closer than `stationCloseZoomDistance`.
    private var stationScale: CGFloat {
        cameraDistance < stationCloseZoomDistance ? 1.4 : 1.0
    }

    // MARK: - Zoom controls

    /// A manual +/- zoom control, like the ones on other map apps — MapKit's
    /// own `.mapControls` doesn't offer one, only pinch-to-zoom, the compass,
    /// scale, and the user-location button.
    private var zoomControls: some View {
        VStack(spacing: 0) {
            Button {
                zoom(by: 0.5)
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 16, weight: .semibold))
                    .frame(width: 36, height: 36)
            }
            Divider().frame(width: 24)
            Button {
                zoom(by: 2)
            } label: {
                Image(systemName: "minus")
                    .font(.system(size: 16, weight: .semibold))
                    .frame(width: 36, height: 36)
            }
        }
        .buttonStyle(.plain)
        .foregroundStyle(.primary)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10))
        .padding(.trailing, 12)
        .padding(.bottom, 24)
    }

    private func zoom(by factor: Double) {
        guard let center = currentCamera?.centerCoordinate ?? lastKnownCenter else { return }
        let newDistance = min(max(cameraDistance * factor, 200), 200_000)
        let newCamera = MapCamera(
            centerCoordinate: center,
            distance: newDistance,
            heading: currentCamera?.heading ?? 0,
            pitch: currentCamera?.pitch ?? 0
        )
        withAnimation(.easeInOut(duration: 0.2)) {
            cameraPosition = .camera(newCamera)
        }
        currentCamera = newCamera
        cameraDistance = newDistance
        lastKnownCenter = center
    }
}

#Preview {
    NavigationStack {
        RouteDetailView(
            route: Route(id: 1, cityId: 1, busreportRouteId: 1, routeName: "АО «ГазМаш» — пос. «Кирпичный»", routeNumber: "12", location: "71.396123 51.157048, 71.396522 51.159953"),
            city: City(id: 1, name: "Астана", serviceURL: "https://example.com"),
            country: Country(id: 1, code: "kz", name: "Казахстан")
        )
    }
    .environmentObject(AppSettingsStore())
}
