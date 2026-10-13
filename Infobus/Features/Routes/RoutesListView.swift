//
//  RoutesListView.swift
//  Infobus
//
//  List of routes for the currently selected city. Reloads automatically
//  whenever the selected city changes (including from Settings, since both
//  read the same SelectedCityStore) via .task(id:).
//
//  No navigation bar/title — a custom compact search field takes its place
//  at the top of the list instead of the standard `.searchable` bar, so the
//  screen isn't carrying a big title above content that doesn't need one.
//
//  Tapping a route opens RouteReferenceView (a details card — direction,
//  endpoints, full stop list), not the live map directly. The live map's
//  own multi-route picker on the "Карта" tab already covers "put a route on
//  the map"; this tab's job now is looking a route up and reading about it,
//  with the map only one button away inside that reference card.
//

import SwiftUI

struct RoutesListView: View {
    @EnvironmentObject private var cityStore: SelectedCityStore
    @StateObject private var viewModel = RoutesListViewModel()
    @State private var searchText = ""

    var body: some View {
        NavigationStack {
            content
                .toolbar(.hidden, for: .navigationBar)
                .navigationDestination(for: Route.self) { route in
                    if let city = cityStore.selectedCity, let country = cityStore.selectedCountry {
                        RouteReferenceView(route: route, city: city, country: country)
                    } else {
                        ContentUnavailableView("Город не выбран", systemImage: "mappin.slash")
                    }
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
                    // `message` is a plain `String` from the view model —
                    // `Text(String)` never looks anything up in
                    // Localizable.xcstrings, so this stayed in Russian
                    // regardless of the in-app language despite the catalog
                    // already having translations for this exact text.
                    Text(LocalizedStringKey(message))
                } actions: {
                    Button("Повторить", action: reload)
                }
            case .loaded(let routes):
                if routes.isEmpty {
                    ContentUnavailableView("Маршруты не найдены", systemImage: "bus")
                } else {
                    VStack(spacing: 0) {
                        RouteSearchField(text: $searchText)
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
                    }
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

private struct RouteSearchField: View {
    @Binding var text: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Номер или название маршрута", text: $text)
                .textFieldStyle(.plain)
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(10)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10))
        .padding(.horizontal)
        .padding(.top, 8)
        .padding(.bottom, 4)
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
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            Spacer()
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    RoutesListView()
        .environmentObject(SelectedCityStore())
}
