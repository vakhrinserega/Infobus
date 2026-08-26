//
//  RouteDetailView.swift
//  Infobus
//
//  The mnemoscheme: a vertical schematic line of stations for one route,
//  with a direction toggle, live buses positioned between the stations
//  they're currently between, inline arrival estimates where data exists,
//  and the rider's own nearest station highlighted with an auto-return
//  scroll behavior.
//

import SwiftUI
import CoreLocation

struct RouteDetailView: View {
    let route: Route
    let city: City
    let country: Country

    @EnvironmentObject private var settings: AppSettingsStore
    @StateObject private var viewModel: RouteDetailViewModel
    @StateObject private var locationProvider = UserLocationProvider()
    @State private var selectedStop: RouteStop?
    @State private var returnToCurrentTask: Task<Void, Never>?

    private let rowHeight: CGFloat = 76
    private let trackX: CGFloat = 28

    init(route: Route, city: City, country: Country) {
        self.route = route
        self.city = city
        self.country = country
        _viewModel = StateObject(wrappedValue: RouteDetailViewModel(route: route, city: city, country: country))
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("Направление", selection: $viewModel.direction) {
                Text(RouteDirection.forward.displayName).tag(RouteDirection.forward)
                Text(RouteDirection.backward.displayName).tag(RouteDirection.backward)
            }
            .pickerStyle(.segmented)
            .padding()
            .onChange(of: viewModel.direction) { _, _ in
                viewModel.directionChanged()
            }

            content
        }
        .navigationTitle(route.routeNumber)
        .navigationBarTitleDisplayMode(.inline)
        .task { await viewModel.loadStops() }
        .onAppear {
            viewModel.startPolling()
            if settings.useMyLocation { locationProvider.start() }
        }
        .onDisappear {
            viewModel.stopPolling()
            locationProvider.stop()
            returnToCurrentTask?.cancel()
        }
        .onReceive(locationProvider.$currentCoordinate) { newValue in
            if let coordinate = newValue {
                viewModel.updateCurrentStation(from: coordinate)
            }
        }
        .sheet(item: $selectedStop) { stop in
            StationPredictionSheet(
                stop: stop,
                predictions: viewModel.predictionsByStationId[stop.station.id] ?? []
            )
        }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.stopsState {
        case .idle, .loading:
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed(let message):
            ContentUnavailableView {
                Label("Не удалось загрузить остановки", systemImage: "exclamationmark.triangle")
            } description: {
                Text(message)
            } actions: {
                Button("Повторить") { Task { await viewModel.loadStops() } }
            }
        case .loaded(let stops):
            if stops.isEmpty {
                ContentUnavailableView("Остановки не найдены", systemImage: "mappin.slash")
            } else {
                mnemoscheme(stops: stops)
            }
        }
    }

    private func mnemoscheme(stops: [RouteStop]) -> some View {
        let totalHeight = CGFloat(stops.count) * rowHeight
        let placed = viewModel.placedBuses(for: stops)

        return ScrollViewReader { proxy in
            ScrollView {
                ZStack(alignment: .topLeading) {
                    Rectangle()
                        .fill(Color.secondary.opacity(0.3))
                        .frame(width: 3, height: totalHeight)
                        .offset(x: trackX - 1.5, y: 0)

                    VStack(spacing: 0) {
                        ForEach(stops) { stop in
                            StationRow(
                                stop: stop,
                                isCurrent: stop.id == viewModel.currentStationId,
                                predictions: viewModel.predictionsByStationId[stop.station.id] ?? [],
                                trackX: trackX
                            )
                            .frame(height: rowHeight)
                            .contentShape(Rectangle())
                            .onTapGesture { selectedStop = stop }
                            .id(stop.id)
                        }
                    }

                    ForEach(placed) { placedBus in
                        BusMarker(isOffRoute: placedBus.isOffRoute)
                            .position(x: trackX, y: yPosition(beforeIndex: placedBus.beforeIndex, t: placedBus.t))
                    }
                }
                .frame(height: totalHeight)
                .padding(.vertical, 12)
            }
            .simultaneousGesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { _ in scheduleReturnToCurrentStation(proxy: proxy) }
            )
            .onChange(of: viewModel.currentStationId) { _, newId in
                // Only auto-follow live position updates when the rider isn't
                // mid-interaction — while returnToCurrentTask is pending (set by
                // a drag below), a live update here would fight a manual scroll
                // instead of waiting out the 2s idle window like it's supposed to.
                guard let newId, returnToCurrentTask == nil else { return }
                withAnimation { proxy.scrollTo(newId, anchor: .bottom) }
            }
            .onAppear {
                if let id = viewModel.currentStationId {
                    proxy.scrollTo(id, anchor: .bottom)
                }
            }
        }
    }

    private func yPosition(beforeIndex: Int, t: Double) -> CGFloat {
        let centerBefore = CGFloat(beforeIndex) * rowHeight + rowHeight / 2
        let centerAfter = CGFloat(beforeIndex + 1) * rowHeight + rowHeight / 2
        return centerBefore + (centerAfter - centerBefore) * CGFloat(t)
    }

    /// Any manual drag restarts a 2-second countdown; if it elapses
    /// uninterrupted, snap back to whatever the rider's current station is
    /// AT THAT TIME (read fresh, not the value captured when the drag
    /// started — the live position may well have moved on during the wait).
    private func scheduleReturnToCurrentStation(proxy: ScrollViewProxy) {
        returnToCurrentTask?.cancel()
        returnToCurrentTask = Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard !Task.isCancelled else { return }
            if let currentId = viewModel.currentStationId {
                withAnimation { proxy.scrollTo(currentId, anchor: .bottom) }
            }
            returnToCurrentTask = nil
        }
    }
}

private struct StationRow: View {
    let stop: RouteStop
    let isCurrent: Bool
    let predictions: [Prediction]
    let trackX: CGFloat

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Circle()
                .fill(isCurrent ? Color.accentColor : Color.secondary)
                .frame(width: isCurrent ? 16 : 10, height: isCurrent ? 16 : 10)
                .frame(width: trackX * 2, alignment: .center)

            VStack(alignment: .leading, spacing: 2) {
                Text(stop.station.name)
                    .font(isCurrent ? .headline : .body)
                    .lineLimit(1)
                if let etaText {
                    Text(etaText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
        // Trailing-only padding: the row must start flush at x = 0 so the
        // circle's frame (width trackX * 2, starting at 0) centers exactly on
        // trackX — the same x the track line and bus markers use. A leading
        // inset here would shift the dot right of the line/markers, which is
        // exactly the bug a review caught in an earlier draft of this row.
        .padding(.trailing)
    }

    private var etaText: String? {
        let values = predictions.map(\.prediction).sorted()
        guard !values.isEmpty else { return nil }
        let formatted = values.prefix(2).map { "\(Int($0.rounded())) мин" }.joined(separator: ", ")
        return "≈ \(formatted)"
    }
}

private struct BusMarker: View {
    let isOffRoute: Bool

    var body: some View {
        Image(systemName: "bus.fill")
            .font(.caption)
            .foregroundStyle(.white)
            .padding(6)
            .background(Circle().fill(isOffRoute ? Color.gray : Color.orange))
            .overlay {
                if isOffRoute {
                    Circle().strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [3, 2]))
                        .foregroundStyle(.gray)
                }
            }
    }
}

#Preview {
    NavigationStack {
        RouteDetailView(
            route: Route(id: 1, cityId: 1, busreportRouteId: 1, routeName: "АО «ГазМаш» — пос. «Кирпичный»", routeNumber: "12", location: ""),
            city: City(id: 1, name: "Астана", serviceURL: "https://example.com"),
            country: Country(id: 1, code: "kz", name: "Казахстан")
        )
    }
    .environmentObject(AppSettingsStore())
}
