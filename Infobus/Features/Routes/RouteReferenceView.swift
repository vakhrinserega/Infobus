//
//  RouteReferenceView.swift
//  Infobus
//
//  What tapping a route in the "Маршруты" list opens — a reference card,
//  not the live map. Now that adding routes to the map (up to 5, with
//  colors) already happens on the "Карта" tab itself, this tab's own job
//  is different: look a route up and read its details — schedule (when the
//  city has one), direction, endpoints, full stop order — with a button to
//  jump into the live map only if that's what's actually wanted next.
//
//  Earlier this screen's own comment claimed the API had no schedule data
//  at all — wrong, confirmed by fetching Kokshetau's `/routes` live: every
//  route there carries a real `schedule` (interval, planned bus count,
//  first/last departure at each terminus). It's just per-city: the same
//  field on Astana's routes is always present but null, since it depends on
//  whether that city's operator entered timetable data on their end. So the
//  schedule card below only appears when `route.schedule` is actually there.
//
//  The route number appears exactly once now — in the (centered, inline)
//  nav bar title as "Маршрут № N" — rather than also repeated large in the
//  page content below; the content header just carries the route's name.
//
//  The plain "endpoint → endpoint" line that used to sit between the
//  direction picker and the stop list was dropped — it duplicated the
//  start/end station names the schedule card already shows above it (when
//  a schedule exists), and on cities without one it added little beyond
//  what the first and last rows of the stop list already say.
//

import SwiftUI

struct RouteReferenceView: View {
    let route: Route
    let city: City
    let country: Country

    @StateObject private var viewModel = RouteReferenceViewModel()
    @State private var selectedDirectionIndex = 0
    @State private var selectedStation: Station?
    /// Needed to properly localize the schedule card's "~N мин" interval —
    /// see `scheduleSummary` below for why this can't just be baked into a
    /// plain `String` the way it used to be.
    @Environment(\.locale) private var locale

    var body: some View {
        content
            .navigationTitle("Маршрут № \(route.routeNumber)")
            .navigationBarTitleDisplayMode(.inline)
            .task {
                await viewModel.load(route: route, city: city, country: country)
            }
            .sheet(item: $selectedStation) { station in
                StationPredictionSheet(
                    station: station,
                    fetch: { await viewModel.fetchPredictions(stationId: station.id, city: city, country: country) },
                    // Same single-route accent-color convention RouteDetailView
                    // already uses — this reference card only ever concerns
                    // one route, so there's no multi-route color to pick from.
                    colorForRoute: { routeId in routeId == route.busreportRouteId ? Color.accentColor : nil }
                )
            }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .idle, .loading:
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed(let message):
            ContentUnavailableView {
                Label("Не удалось загрузить маршрут", systemImage: "exclamationmark.triangle")
            } description: {
                // `message` is a plain `String` from the view model —
                // `Text(String)` never looks anything up in the catalog.
                Text(LocalizedStringKey(message))
            } actions: {
                Button("Повторить") {
                    Task { await viewModel.load(route: route, city: city, country: country) }
                }
            }
        case .loaded(let directions):
            if directions.isEmpty {
                ContentUnavailableView("Остановки не найдены", systemImage: "mappin.slash")
            } else {
                directionsView(directions)
            }
        }
    }

    private func directionsView(_ directions: [RouteDirectionStops]) -> some View {
        let currentIndex = directions.indices.contains(selectedDirectionIndex) ? selectedDirectionIndex : 0
        let current = directions[currentIndex]

        return ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header

                // Schedule describes the route as a whole (the API doesn't
                // split it by direction), so it sits above the direction
                // picker rather than inside either direction's content.
                scheduleSummary

                if directions.count > 1 {
                    Picker("Направление", selection: $selectedDirectionIndex) {
                        ForEach(Array(directions.enumerated()), id: \.offset) { index, direction in
                            Text(direction.isForward ? "Туда" : "Обратно").tag(index)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal)
                }

                stopsList(current)

                mapButton
                    .padding(.horizontal)
                    .padding(.top, 4)
            }
            .padding(.vertical)
        }
    }

    private var header: some View {
        Text(route.routeName)
            .font(.title3.bold())
            .padding(.horizontal)
    }

    // MARK: - Schedule

    @ViewBuilder
    private var scheduleSummary: some View {
        if let schedule = route.schedule {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 20) {
                    // `String(localized:locale:)` (not a plain interpolated
                    // literal) so the "мин" unit actually translates too —
                    // it's built from a dynamic number, so it could never go
                    // through the usual Text("literal") path that the rest
                    // of this screen's static labels use. Passing `locale`
                    // explicitly matters here: this app has its own in-app
                    // language override (Settings → Язык) independent of
                    // the device's system language, and `String(localized:)`
                    // without an explicit locale ignores that override and
                    // just uses the system one.
                    //
                    // The "~" is prepended as a plain literal rather than
                    // baked into its own "~%lld мин" catalog key — Xcode's
                    // symbol generation strips non-alphanumeric characters
                    // from a key before naming its generated accessor, so
                    // that key and Prediction's own "%lld мин" collided on
                    // the same generated symbol name and failed to build.
                    // Reusing the one key sidesteps that entirely.
                    scheduleStat(
                        systemImage: "timer",
                        value: "~" + String(localized: "\(schedule.interval) мин", locale: locale),
                        label: "Интервал"
                    )
                    scheduleStat(systemImage: "bus", value: "\(schedule.busCount)", label: "Автобусов")
                }
                Divider()
                scheduleTerminalRow(schedule.startStation)
                scheduleTerminalRow(schedule.endStation)
            }
            .padding(12)
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal)
        }
    }

    private func scheduleStat(systemImage: String, value: String, label: LocalizedStringKey) -> some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 0) {
                Text(value)
                    .font(.subheadline.bold())
                Text(label)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func scheduleTerminalRow(_ terminal: RouteScheduleStation) -> some View {
        HStack {
            Text(terminal.stationName)
                .font(.subheadline)
                .lineLimit(1)
            Spacer()
            Text("\(terminal.firstTime)–\(terminal.lastTime)")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Direction

    /// Rows are tappable — same "which routes stop here, and when's the next
    /// bus" sheet the map screens already show for a station pin, now also
    /// reachable from this plain reference list instead of only from a map.
    private func stopsList(_ direction: RouteDirectionStops) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(direction.stations.enumerated()), id: \.element.id) { index, station in
                Button {
                    selectedStation = station
                } label: {
                    HStack(alignment: .top, spacing: 10) {
                        Text("\(index + 1)")
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)
                            .frame(width: 20, alignment: .trailing)
                        Text(station.name)
                            .font(.body)
                            .foregroundStyle(.primary)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.vertical, 6)
                    .padding(.horizontal)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if index < direction.stations.count - 1 {
                    Divider().padding(.leading, 40)
                }
            }
        }
    }

    private var mapButton: some View {
        NavigationLink {
            RouteDetailView(route: route, city: city, country: country)
        } label: {
            Label("Показать на карте", systemImage: "map")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
    }
}

#Preview {
    NavigationStack {
        RouteReferenceView(
            route: Route(
                id: 33006730,
                cityId: 13,
                busreportRouteId: 1,
                routeName: "СШ#12 - Обл.Больница",
                routeNumber: "1",
                location: "69.42881 53.28303, 69.42852 53.28322",
                schedule: RouteSchedule(
                    busCount: 4,
                    interval: 16,
                    startStation: RouteScheduleStation(stationName: "СШ №12_", firstTime: "06:53", lastTime: "21:54"),
                    endStation: RouteScheduleStation(stationName: "Областная Больница..", firstTime: "07:07", lastTime: "22:21")
                )
            ),
            city: City(id: 13, name: "Кокшетау", serviceURL: "https://infobus.kz"),
            country: Country(id: 1, code: "kz", name: "Казахстан")
        )
    }
}
