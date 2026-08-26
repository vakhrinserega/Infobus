//
//  RoutesListView.swift
//  Infobus
//
//  List of routes for the currently selected city. Reloads automatically
//  whenever the selected city changes (including from Settings, since both
//  read the same SelectedCityStore) via .task(id:).
//

import SwiftUI

struct RoutesListView: View {
    @EnvironmentObject private var cityStore: SelectedCityStore
    @StateObject private var viewModel = RoutesListViewModel()
    @State private var searchText = ""

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Маршруты")
                .navigationDestination(for: Route.self) { route in
                    RouteDetailView(route: route)
                }
        }
        .task(id: cityStore.selectionKey) {
            guard let city = cityStore.selectedCity, let country = cityStore.selectedCountry else { return }
            await viewModel.load(city: city, country: country)
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
            switch viewModel.state {
            case .idle, .loading:
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .failed(let message):
                ContentUnavailableView {
                    Label("Не удалось загрузить маршруты", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(message)
                } actions: {
                    Button("Повторить", action: reload)
                }
            case .loaded(let routes):
                if routes.isEmpty {
                    ContentUnavailableView("Маршруты не найдены", systemImage: "bus")
                } else {
                    List(filteredRoutes(routes)) { route in
                        NavigationLink(value: route) {
                            RouteRow(route: route)
                        }
                    }
                    .listStyle(.plain)
                    .overlay {
                        if filteredRoutes(routes).isEmpty {
                            ContentUnavailableView.search(text: searchText)
                        }
                    }
                    .searchable(text: $searchText, prompt: "Номер или название маршрута")
                }
            }
        }
    }

    private func reload() {
        guard let city = cityStore.selectedCity, let country = cityStore.selectedCountry else { return }
        Task { await viewModel.load(city: city, country: country) }
    }

    private func filteredRoutes(_ routes: [Route]) -> [Route] {
        guard !searchText.isEmpty else { return routes }
        return routes.filter {
            $0.routeNumber.localizedCaseInsensitiveContains(searchText) ||
            $0.routeName.localizedCaseInsensitiveContains(searchText)
        }
    }
}

private struct RouteRow: View {
    let route: Route

    var body: some View {
        HStack(spacing: 12) {
            Text(route.routeNumber)
                .font(.headline)
                .frame(minWidth: 40)
                .padding(.vertical, 6)
                .padding(.horizontal, 10)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
            Text(route.routeName)
                .foregroundStyle(.primary)
            Spacer()
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    RoutesListView()
        .environmentObject(SelectedCityStore())
}
