//
//  SearchView.swift
//  Infobus
//
//  "Поиск" tab — pick a departure and destination point and see which
//  route(s) connect them, via the old `pathsbwpoints` endpoint.
//
//  Points are picked by tapping a self-contained map sheet (or "Моё
//  местоположение" for the current GPS fix) — see MapPointPickerSheet —
//  rather than from a station list: the endpoint takes raw coordinates and
//  the backend itself works out which nearby stops to walk to, matching how
//  the old app's own map-tap search worked. A station picker would only
//  have narrowed that down artificially.
//

import SwiftUI
import MapKit
import CoreLocation

struct SearchView: View {
    @EnvironmentObject private var cityStore: SelectedCityStore
    @StateObject private var viewModel = SearchViewModel()
    @State private var pickerTarget: MapPointTarget?
    /// The selected city's own extent, so `MapPointPickerSheet` opens
    /// centered on the right city instead of wherever `.automatic` lands.
    /// Resolved eagerly here on city change so it's *usually* already on
    /// hand the instant a picker sheet opens — but the sheet also resolves
    /// this itself (via the same `CityRegion.fallback`) as a fallback for
    /// when this hasn't finished yet, e.g. the user tapped "Откуда" right
    /// after switching cities, before this had a chance to land. Nil just
    /// means "not resolved yet (or unresolvable)" — never a dead end.
    @State private var cityFallbackRegion: MKCoordinateRegion?
    /// What `cityStore.selectionKey` was the last time the task below
    /// actually ran its body — NOT just a copy of the id SwiftUI passes
    /// in. `.task(id:)` re-runs its whole body every time this view
    /// *reappears*, even when the id hasn't changed at all: switching to
    /// another tab and back is exactly such a reappearance. Without this
    /// guard, that alone called `viewModel.reset()` and wiped out an
    /// in-progress search (points picked, results already shown) for no
    /// reason other than having looked at a different tab for a moment.
    @State private var lastHandledSelectionKey: String?

    var body: some View {
        NavigationStack {
            content
                .toolbar(.hidden, for: .navigationBar)
        }
        .task(id: cityStore.selectionKey) {
            guard cityStore.selectionKey != lastHandledSelectionKey else { return }
            lastHandledSelectionKey = cityStore.selectionKey
            viewModel.reset()
            cityFallbackRegion = nil
            if let city = cityStore.selectedCity, let country = cityStore.selectedCountry {
                cityFallbackRegion = await CityRegion.fallback(for: city, in: country)
            }
        }
        .sheet(item: $pickerTarget) { target in
            MapPointPickerSheet(
                title: target.title,
                initialCoordinate: target.isFrom ? viewModel.fromPoint?.coordinate : viewModel.toPoint?.coordinate,
                fallbackRegion: cityFallbackRegion,
                city: cityStore.selectedCity,
                country: cityStore.selectedCountry
            ) { coordinate, label in
                let point = SearchPoint(coordinate: coordinate, label: label)
                if target.isFrom {
                    viewModel.fromPoint = point
                } else {
                    viewModel.toPoint = point
                }
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if cityStore.selectedCity == nil {
            ContentUnavailableView(
                "Город не выбран",
                systemImage: "mappin.slash",
                description: Text("Выберите город на вкладке «Настройки».")
            )
        } else {
            VStack(spacing: 0) {
                form
                Divider()
                results
            }
        }
    }

    // MARK: - Form

    private var form: some View {
        VStack(spacing: 10) {
            pointRow(
                title: "Откуда",
                point: viewModel.fromPoint,
                systemImage: "circle.fill",
                tint: .green
            ) {
                pickerTarget = .from
            }
            pointRow(
                title: "Куда",
                point: viewModel.toPoint,
                systemImage: "mappin.circle.fill",
                tint: .red
            ) {
                pickerTarget = .to
            }

            HStack {
                Button("Сбросить") {
                    viewModel.reset()
                }
                .disabled(viewModel.fromPoint == nil && viewModel.toPoint == nil)

                Spacer()

                Button {
                    guard let city = cityStore.selectedCity else { return }
                    Task { await viewModel.search(city: city) }
                } label: {
                    Label("Найти", systemImage: "magnifyingglass")
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.fromPoint == nil || viewModel.toPoint == nil)
            }
        }
        .padding()
    }

    private func pointRow(
        title: String,
        point: SearchPoint?,
        systemImage: String,
        tint: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .foregroundStyle(tint)
                VStack(alignment: .leading, spacing: 2) {
                    // `title`/`point?.label` are plain `String`s (the row is
                    // shared between "Откуда" and "Куда"), so `Text(_:)` here
                    // would use the raw-string initializer and never look
                    // anything up in Localizable.xcstrings — this was exactly
                    // why these two stayed in Russian regardless of the
                    // in-app language. Re-wrapping in `LocalizedStringKey`
                    // makes it look up the current string as a catalog key
                    // again; a real address in `point.label` just won't
                    // match one and displays unchanged, which is what we
                    // want for that dynamic case anyway.
                    Text(LocalizedStringKey(title))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(LocalizedStringKey(point?.label ?? "Укажите точку на карте"))
                        .foregroundStyle(point == nil ? .secondary : .primary)
                        .lineLimit(1)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(10)
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Results

    @ViewBuilder
    private var results: some View {
        switch viewModel.resultsState {
        case .idle:
            ContentUnavailableView(
                "Найдите маршрут",
                systemImage: "arrow.triangle.swap",
                description: Text("Укажите на карте, откуда и куда вы едете.")
            )
        case .loading:
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed(let message):
            ContentUnavailableView {
                Label("Ошибка поиска", systemImage: "exclamationmark.triangle")
            } description: {
                // Same fix as pointRow above — `message` is a `String` set
                // on the view model, `Text(String)` never localized it.
                Text(LocalizedStringKey(message))
            }
        case .loaded(let paths):
            if paths.isEmpty {
                ContentUnavailableView("Автобусом отсюда добраться не получилось найти", systemImage: "bus")
            } else {
                List(paths) { path in
                    // Wrapped in its own NavigationLink (rather than relying
                    // on List's row-tap) so SearchResultRow stays a plain
                    // display view, reusable without a nav context (e.g. in
                    // its own #Preview).
                    NavigationLink {
                        if let city = cityStore.selectedCity, let country = cityStore.selectedCountry {
                            SearchResultMapView(
                                path: path,
                                fromCoordinate: viewModel.fromPoint?.coordinate,
                                toCoordinate: viewModel.toPoint?.coordinate,
                                city: city,
                                country: country
                            )
                        }
                    } label: {
                        SearchResultRow(
                            path: path,
                            fromCoordinate: viewModel.fromPoint?.coordinate,
                            toCoordinate: viewModel.toPoint?.coordinate
                        )
                    }
                }
                .listStyle(.plain)
            }
        }
    }
}

private enum MapPointTarget: Identifiable {
    case from, to

    var id: Self { self }

    var isFrom: Bool { self == .from }

    var title: String {
        switch self {
        case .from: return "Откуда"
        case .to: return "Куда"
        }
    }
}

/// One row = one complete way to get there. A direct path renders as a
/// single leg; a path with a transfer chains each leg's route/stops block
/// with a "Пересадка" marker between them, matching how the old
/// Objective-C app's `processSearchResults:` used to chain multi-leg paths —
/// just inline in the row instead of a separate page per path.
private struct SearchResultRow: View {
    let path: SearchPath
    /// The rider's own picked points for this search (not the stop
    /// coordinates) — used to show how far they'd have to walk to/from the
    /// stops this route actually serves, since `pathsbwpoints` only ever
    /// snaps to a *nearby* stop, not the exact point tapped.
    let fromCoordinate: CLLocationCoordinate2D?
    let toCoordinate: CLLocationCoordinate2D?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let fromCoordinate, let firstLeg = path.legs.first {
                walkRow(
                    prefix: "Пешком до остановки",
                    meters: RouteGeometry.distance(fromCoordinate, firstLeg.departureStop.coordinate)
                )
            }

            ForEach(Array(path.legs.enumerated()), id: \.offset) { index, leg in
                if index > 0 {
                    Label {
                        Text("Пересадка на «\(leg.departureStop.name)»")
                    } icon: {
                        Image(systemName: "arrow.triangle.swap")
                    }
                    .font(.caption)
                    .foregroundStyle(.orange)
                }
                legRow(leg)
            }

            if let toCoordinate, let lastLeg = path.legs.last {
                walkRow(
                    prefix: "Пешком от остановки",
                    meters: RouteGeometry.distance(lastLeg.arrivalStop.coordinate, toCoordinate)
                )
            }
        }
        .padding(.vertical, 4)
    }

    private func legRow(_ leg: SearchResultItem) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text(leg.route.number)
                    .font(.headline)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 6))
                Text(leg.route.name)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            HStack(spacing: 6) {
                Text(leg.departureStop.name)
                Image(systemName: "arrow.right")
                    .foregroundStyle(.secondary)
                Text(leg.arrivalStop.name)
            }
            .font(.subheadline)
            Text("\(leg.numStops) ост.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func walkRow(prefix: LocalizedStringKey, meters: Double) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "figure.walk")
                .font(.caption2)
            // `prefix` used to be a plain `String` — the two call sites
            // below passed literal Russian text straight in, which
            // *looked* harmless (string interpolation makes `Text(...)`
            // resolve either way) but actually meant Xcode's String
            // Catalog extraction never saw "Пешком до/от остановки" as a
            // localizable key at all, so it stayed Russian regardless of
            // the in-app language. `LocalizedStringKey` fixes that at the
            // type level; concatenating `Text` values (rather than
            // interpolating `prefix` into one shared string) keeps each
            // piece's own localization independent and unambiguous.
            Text(prefix) + Text(" — ") + Text(formattedDistance(meters))
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private func formattedDistance(_ meters: Double) -> String {
        meters >= 1000 ? String(format: "%.1f км", meters / 1000) : "\(Int(meters.rounded())) м"
    }
}

#Preview {
    SearchView()
        .environmentObject(SelectedCityStore())
}
