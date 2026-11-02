//
//  MapView.swift
//  Infobus
//
//  "Карта" tab — the app's first/primary tab, edge-to-edge: the map fills
//  the whole screen (no title bar), with the route chips floating over it
//  in a translucent bar that respects the safe area, rather than the map
//  being squeezed into whatever space is left under a title/toolbar.
//
//  That bar sits at the BOTTOM, not the top — thumb reach while holding
//  the phone one-handed, per direct feedback. "Добавить" is the leftmost
//  element (a fixed, predictable spot) with the up-to-5 selected route
//  chips scrolling out to its right, rather than the reverse. The manual
//  zoom controls, which used to anchor bottom-trailing, moved to a
//  vertically-centered trailing overlay instead so they land clear of both
//  the (now-freed) top and the new bottom bar regardless of that bar's
//  exact height on a given device.
//
//  MapKit's own `MapUserLocationButton()` used to live in `.mapControls`
//  alongside the compass/scale — system-positioned top-trailing, styled
//  differently from our own zoom pair, and reported as not responding to
//  taps. Replaced with our own circular locate-me button (see
//  `mapButtonsCluster`), grouped with zoom in the same trailing cluster so
//  all three read as one control family (same circular shape, same
//  material) instead of two different button languages fighting for the
//  same corner.
//
//  RouteMapTrack is a plain ObservableObject held in an array here, not
//  individual @StateObject properties (which wouldn't work for a dynamic,
//  variable-length selection) — so this view can't rely on SwiftUI's usual
//  @StateObject/@ObservedObject wiring to notice when a track's own
//  @Published properties change. Instead every track's objectWillChange is
//  merged into one subscription that bumps `updateTick`, a plain @State
//  Int with no other purpose than forcing this view's body to re-run (which
//  then reads each track's current buses/stopsState fresh, regardless of
//  property-wrapper machinery).
//
//  Map content is added in three passes across ALL tracks — every line,
//  then every station, then every bus — rather than per-track, so every
//  bus annotation (from any of the up-to-5 routes) is declared after every
//  station annotation and always renders on top. Station pins only show
//  once zoomed in close enough, and bus icons shrink at a distance — both
//  driven by the map's live camera distance.
//
//  The Map itself is always on screen, even before routes/selection have
//  loaded — an empty map while data loads reads far better than a flash of
//  "Маршруты не выбраны" that then gets replaced a second later once the
//  previously-selected routes come back from cache. That placeholder only
//  shows once loading has genuinely finished and there's really nothing
//  selected.
//

import SwiftUI
import MapKit
import Combine

struct MapView: View {
    @EnvironmentObject private var cityStore: SelectedCityStore
    @EnvironmentObject private var settings: AppSettingsStore
    @StateObject private var routesViewModel = RoutesListViewModel()
    @StateObject private var selectedRoutesStore = SelectedRoutesStore()
    @StateObject private var locationProvider = UserLocationProvider()

    @State private var tracks: [RouteMapTrack] = []
    @State private var trackObservation: AnyCancellable?
    @State private var updateTick = 0
    @State private var cameraPosition: MapCameraPosition = .automatic
    @State private var cameraDistance: Double = 3000
    @State private var currentCamera: MapCamera?
    /// A fallback center coordinate, seeded whenever the camera is set
    /// programmatically (route-fit, zoom, locate-me) — NOT dependent on
    /// `.onMapCameraChange` ever firing. `currentCamera` is only ever
    /// populated by that callback, and on at least some devices/OS builds
    /// it appears to fire unreliably (or not before the first tap), which
    /// left `zoom(by:)`'s hard `guard let currentCamera` silently doing
    /// nothing — the plus/minus buttons looked broken while the
    /// locate-me button, which never hard-required `currentCamera`, kept
    /// working. This gives `zoom(by:)` the same kind of graceful fallback.
    @State private var lastKnownCenter: CLLocationCoordinate2D?
    @State private var isPickerPresented = false
    /// While now is before this, `.onMapCameraChange` ignores its own
    /// ticks. The zoom and locate-me buttons already know their exact
    /// target distance/coordinate and write it to state immediately
    /// themselves — so every mid-flight tick `.onMapCameraChange` fires
    /// during that same 0.2–0.3s camera animation is a redundant write of
    /// a value we already set. Each one still invalidates `mapContent`'s
    /// body, forcing SwiftUI to rebuild the ENTIRE map content (every
    /// polyline/station/bus across up to 5 routes) on every single frame
    /// of the animation — that rebuild cost, repeated many times over
    /// one button tap, is what actually made the zoom buttons feel
    /// laggy, not the camera move itself. Pinch-to-zoom and manual
    /// dragging are untouched by this — only our OWN programmatic moves
    /// set this deadline.
    @State private var suppressCameraChangeUntil: Date = .distantPast

    /// Station pins only render once the camera is closer than this (meters).
    /// Kept generous on purpose — stations should show up while still fairly
    /// zoomed out rather than only after zooming in a lot.
    private let stationVisibleMaxDistance: Double = 10000

    /// Below this camera distance, station pins step up to their larger
    /// size — "close" zoom, as opposed to the "medium" zoom range between
    /// this and `stationVisibleMaxDistance`, where they stay at their
    /// normal size (a two-step change, not a continuous ramp like
    /// `busScale`, per how this was actually asked for).
    private let stationCloseZoomDistance: Double = 2000

    var body: some View {
        NavigationStack {
            Group {
                if cityStore.selectedCity == nil {
                    ContentUnavailableView(
                        "Город не выбран",
                        systemImage: "mappin.slash",
                        description: Text("Выберите город на вкладке «Настройки».")
                    )
                } else {
                    ZStack(alignment: .bottom) {
                        mapContent
                            .ignoresSafeArea()
                        chipsRow
                    }
                }
            }
            .toolbar(.hidden, for: .navigationBar)
        }
        .task(id: cityStore.selectionKey) {
            guard let city = cityStore.selectedCity, let country = cityStore.selectedCountry else { return }
            selectedRoutesStore.load(country: country, city: city)
            await routesViewModel.load(city: city, country: country)
            syncTracks(city: city, country: country)
        }
        .onChange(of: selectedRoutesStore.selectedRouteIds) { _, _ in
            guard let city = cityStore.selectedCity, let country = cityStore.selectedCountry else { return }
            syncTracks(city: city, country: country)
        }
        .onAppear {
            if settings.useMyLocation { locationProvider.start() }
        }
        .onDisappear {
            locationProvider.stop()
            tracks.forEach { $0.stopPolling() }
        }
        .sheet(isPresented: $isPickerPresented) {
            Group {
                if case .loaded(let routes) = routesViewModel.state {
                    RoutePickerSheet(routes: routes, store: selectedRoutesStore)
                } else {
                    ProgressView()
                }
            }
        }
    }

    // MARK: - Chips

    @ViewBuilder
    private var chipsRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 14) {
                // Fixed leftmost position — reachable without shifting grip
                // one-handed — with selected routes trailing off to the
                // right rather than the button drifting as the list grows.
                // Extra spacing (14pt, vs. 8pt between chips themselves)
                // and a divider mark it as a separate control from the
                // scrolling chip list right next to it, not just another
                // item in the same row — a real risk when several tap
                // targets (this button, each chip, each chip's own remove
                // "×") sit this close together in a horizontal scroller.
                Button {
                    isPickerPresented = true
                } label: {
                    Label("Добавить", systemImage: "plus")
                        .font(.subheadline)
                }
                .buttonStyle(.bordered)
                .disabled(selectedRoutesStore.isFull)

                if !tracks.isEmpty {
                    Divider().frame(height: 24)
                }

                ForEach(tracks) { track in
                    RouteChip(route: track.route, color: colorFor(track)) {
                        selectedRoutesStore.remove(routeId: track.id)
                    }
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
        .background(.ultraThinMaterial)
    }

    // MARK: - Map

    @ViewBuilder
    private var mapContent: some View {
        // Reading `updateTick` here isn't necessary for correctness (the
        // property wrapper doesn't matter — see header), but keeps the
        // dependency visible to a reader.
        let _ = updateTick

        ZStack {
            Map(position: $cameraPosition) {
                ForEach(tracks) { track in
                    // A darker casing under the colored line keeps each
                    // route legible against whatever the basemap looks like
                    // underneath it, the same way transit maps outline
                    // their lines.
                    MapPolyline(coordinates: track.route.coordinates)
                        .stroke(Color.black.opacity(0.25), lineWidth: 6)
                    MapPolyline(coordinates: track.route.coordinates)
                        .stroke(colorFor(track), lineWidth: 4)
                }

                if cameraDistance < stationVisibleMaxDistance {
                    ForEach(tracks) { track in
                        if case .loaded(let stations) = track.stopsState {
                            ForEach(stations) { station in
                                Annotation(station.name, coordinate: station.coordinate, anchor: .bottom) {
                                    StationAnnotationView(
                                        station: station,
                                        isCurrent: false,
                                        fetch: { await track.fetchPredictions(stationId: station.id) },
                                        colorForRoute: { routeId in selectedRoutesStore.colorSlotByRouteId[routeId]?.color }
                                    )
                                    .scaleEffect(stationScale)
                                    .zIndex(0)
                                }
                            }
                        }
                    }
                }

                ForEach(tracks) { track in
                    ForEach(track.buses) { busPin in
                        Annotation("", coordinate: busPin.coordinate, anchor: .center) {
                            BusAnnotationView(
                                bus: busPin.bus,
                                isOffRoute: busPin.isOffRoute,
                                bearing: busPin.bearing,
                                routeColor: colorFor(track),
                                occupancyPercent: busPin.bus.filling,
                                mapHeading: currentCamera?.heading ?? 0
                            )
                            .scaleEffect(busScale)
                            .zIndex(1)
                        }
                    }
                }

                UserAnnotation()
            }
            .mapControls {
                MapCompass()
                MapScaleView()
            }
            .onMapCameraChange(frequency: .continuous) { context in
                guard Date() >= suppressCameraChangeUntil else { return }
                cameraDistance = context.camera.distance
                currentCamera = context.camera
            }
            .overlay(alignment: .trailing) {
                mapButtonsCluster
            }

            if hasFinishedLoadingRoutes && tracks.isEmpty {
                // ContentUnavailableView's own text/icon colors adapt to the
                // app's light/dark appearance, not to whatever's actually
                // behind them — sitting directly over live map imagery
                // (bright terrain, satellite photos, a light-mode street
                // map) that made it unreadable in practice. A material card
                // behind it guarantees contrast against any basemap.
                ContentUnavailableView(
                    "Маршруты не выбраны",
                    systemImage: "map",
                    description: Text("Нажмите «Добавить», чтобы выбрать до 5 маршрутов.")
                )
                .padding(24)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
                .padding(.horizontal, 32)
            }
        }
    }

    /// True only once route data has actually finished loading — used to
    /// tell "still loading, show a blank map" apart from "loaded, and there
    /// really is nothing selected."
    private var hasFinishedLoadingRoutes: Bool {
        if case .loaded = routesViewModel.state { return true }
        return false
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

    private func colorFor(_ track: RouteMapTrack) -> Color {
        selectedRoutesStore.colorSlotByRouteId[track.id]?.color ?? .accentColor
    }

    // MARK: - Map buttons (locate me + zoom)

    /// Three circular buttons, same shape/material, read as one control
    /// family: locate-me on top, then the manual +/- zoom pair — MapKit's
    /// `.mapControls` doesn't offer a zoom control at all, only pinch-to-
    /// zoom, the compass, and scale. Anchored to the vertical center of the
    /// trailing edge (not a corner) so the whole cluster stays clear of the
    /// bottom chips bar and the top status area alike, regardless of the
    /// exact height either ends up being on a given device.
    private var mapButtonsCluster: some View {
        VStack(spacing: 10) {
            circularMapButton(systemImage: "location.fill", action: centerOnUserLocation)
            circularMapButton(systemImage: "plus", action: { zoom(by: 0.5) })
            circularMapButton(systemImage: "minus", action: { zoom(by: 2) })
        }
        .padding(.trailing, 12)
    }

    /// Deliberately NOT a `Button` — these sometimes didn't register a tap
    /// at all, while pinch-zoom and MapKit's own native double-tap-to-zoom
    /// on the map underneath always worked. That's the signature of this
    /// button losing a gesture-recognizer race against the `Map`'s own
    /// native pan/pinch/double-tap recognizers, which sit on the exact
    /// same screen region underneath this overlay — a plain `Button`'s tap
    /// gesture can occasionally lose that race and the touch gets consumed
    /// by the map instead. `.highPriorityGesture` tells SwiftUI this
    /// view's tap must win outright instead of competing for the touch.
    private func circularMapButton(systemImage: String, action: @escaping () -> Void) -> some View {
        Image(systemName: systemImage)
            .font(.system(size: 18, weight: .semibold))
            .frame(width: 46, height: 46)
            .foregroundStyle(.primary)
            .background(.thinMaterial, in: Circle())
            .shadow(radius: 1)
            .contentShape(Circle())
            .highPriorityGesture(TapGesture().onEnded(action))
            .accessibilityAddTraits(.isButton)
    }

    /// Drives the zoom buttons off `cameraDistance` rather than
    /// `currentCamera?.distance` — both are refreshed by the same
    /// `.onMapCameraChange` callback, but `cameraDistance` is also the
    /// value `stationScale`/`busScale` already depend on and are visibly
    /// working correctly off, so it's the one known to actually be fresh
    /// at tap time.
    ///
    /// No longer hard-requires `currentCamera` for the center coordinate
    /// either — it previously did (`guard let currentCamera else {
    /// return }`), which meant the whole button silently did nothing on
    /// any tap before `.onMapCameraChange` had fired at least once (and,
    /// it turned out, sometimes it just never reliably fires at all).
    /// Falls back to `lastKnownCenter` — seeded by every programmatic
    /// camera move this view makes — the same graceful-fallback approach
    /// `centerOnUserLocation()` already used, which is exactly why that
    /// button kept working while these two didn't.
    private func zoom(by factor: Double) {
        guard let center = currentCamera?.centerCoordinate ?? lastKnownCenter else {
            return
        }
        let newDistance = min(max(cameraDistance * factor, 200), 200_000)
        let newCamera = MapCamera(
            centerCoordinate: center,
            distance: newDistance,
            heading: currentCamera?.heading ?? 0,
            pitch: currentCamera?.pitch ?? 0
        )
        // Mutes `.onMapCameraChange`'s own ticks for the duration of this
        // move — see `suppressCameraChangeUntil`'s own comment for why
        // those were the actual source of the lag, not the camera move
        // itself.
        suppressCameraChangeUntil = Date().addingTimeInterval(0.3)
        withAnimation(.easeInOut(duration: 0.2)) {
            cameraPosition = .camera(newCamera)
            // Animated together with the camera now, instead of snapping
            // the instant the button is tapped — `busScale`/`stationScale`
            // read this, so their own `.scaleEffect` now eases in step
            // with the camera instead of jumping ahead of it.
            cameraDistance = newDistance
        }
        // Self-seed rather than waiting on `.onMapCameraChange` — so a
        // second rapid tap (or `centerOnUserLocation()` right after)
        // still has a fresh camera to work from even if that callback
        // is slow, or never comes, on this device.
        currentCamera = newCamera
        lastKnownCenter = center
    }

    /// Recenters on the rider's last known location at the current zoom
    /// level — silently does nothing if location isn't available yet (no
    /// fix, permission denied, or the "Определять моё местоположение"
    /// setting is off), same as MapKit's own button would in that case.
    private func centerOnUserLocation() {
        guard let coordinate = locationProvider.currentCoordinate else { return }
        let newCamera = MapCamera(
            centerCoordinate: coordinate,
            distance: currentCamera?.distance ?? 1500,
            heading: currentCamera?.heading ?? 0,
            pitch: currentCamera?.pitch ?? 0
        )
        suppressCameraChangeUntil = Date().addingTimeInterval(0.4)
        withAnimation(.easeInOut(duration: 0.3)) {
            cameraPosition = .camera(newCamera)
        }
        currentCamera = newCamera
        lastKnownCenter = coordinate
    }

    // MARK: - Track lifecycle

    private func syncTracks(city: City, country: Country) {
        guard case .loaded(let routes) = routesViewModel.state else { return }
        let routesById = Dictionary(uniqueKeysWithValues: routes.map { ($0.busreportRouteId, $0) })

        var updated: [RouteMapTrack] = []
        for id in selectedRoutesStore.selectedRouteIds {
            guard let route = routesById[id] else { continue }
            if let existing = tracks.first(where: { $0.id == id }) {
                updated.append(existing)
            } else {
                let track = RouteMapTrack(route: route, city: city, country: country)
                updated.append(track)
                Task {
                    await track.loadStops()
                    track.startPolling()
                }
            }
        }

        for old in tracks where !updated.contains(where: { $0.id == old.id }) {
            old.stopPolling()
        }

        tracks = updated
        observeTracks()
        updateCameraToFitAllTracks()
    }

    private func observeTracks() {
        trackObservation = Publishers.MergeMany(tracks.map(\.objectWillChange))
            .receive(on: DispatchQueue.main)
            .sink { _ in
                // Every live bus refresh (each selected route polls every
                // 5s, independently) bumps `updateTick`, which forces
                // THIS screen's body — and so `mapContent`'s entire
                // polyline/station/bus tree, across every selected route
                // — to rebuild. That's already expensive on its own; if
                // one of these refreshes lands in the same moment as a
                // zoom-button tap, the two expensive rebuilds can pile up
                // on the same run loop turn, which was a plausible reason
                // a tap sometimes seemed to do nothing at all — the app
                // was simply still busy with the OTHER rebuild when that
                // tap needed handling. Deferring a refresh that lands
                // inside a zoom's own settle window lets the animation
                // finish on its own first, instead of the two colliding.
                if Date() < suppressCameraChangeUntil {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        updateTick &+= 1
                    }
                } else {
                    updateTick &+= 1
                }
            }
    }

    private func updateCameraToFitAllTracks() {
        let allCoordinates = tracks.flatMap { $0.route.coordinates }
        guard let region = RouteGeometry.boundingRegion(for: allCoordinates) else { return }
        cameraPosition = .region(region)
        // Seeds the zoom buttons' fallback center immediately, without
        // waiting on `.onMapCameraChange` — see `lastKnownCenter`'s own
        // comment for why that callback can't be relied on alone.
        lastKnownCenter = region.center
    }
}

private struct RouteChip: View {
    let route: Route
    let color: Color
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 10, height: 10)
            Text(route.routeNumber).font(.subheadline.bold())
            Button(action: onRemove) {
                // The glyph itself stays small, but its tap target is
                // padded out well past it — a bare 12pt SF Symbol is an
                // easy miss (or an easy accidental hit on a neighboring
                // chip) inside a horizontally scrolling row like this one.
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
                    .padding(6)
                    .contentShape(Rectangle())
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.thinMaterial, in: Capsule())
    }
}

#Preview {
    MapView()
        .environmentObject(SelectedCityStore())
        .environmentObject(AppSettingsStore())
}
