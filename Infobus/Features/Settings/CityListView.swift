//
//  CityListView.swift
//  Infobus
//
//  Second step of the city picker: cities within one country. Selecting a
//  city persists it via the view model, then calls `onCitySelected` — owned
//  by SettingsView, which clears the whole NavigationPath so this and the
//  country list both pop at once, straight back to Settings.
//

import SwiftUI

struct CityListView: View {
    let country: Country
    @EnvironmentObject private var cityStore: SelectedCityStore
    @ObservedObject var viewModel: SettingsViewModel
    let onCitySelected: () -> Void

    var body: some View {
        List {
            switch viewModel.citiesState {
            case .idle, .loading:
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
            case .failed(let message):
                retryRow(message: message) {
                    Task { await viewModel.loadCities(for: country) }
                }
            case .loaded(let cities):
                ForEach(cities) { city in
                    Button {
                        viewModel.selectCity(city, country: country, store: cityStore)
                        onCitySelected()
                    } label: {
                        HStack {
                            Text(city.name)
                            Spacer()
                            if cityStore.selectedCity?.id == city.id {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.tint)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.primary)
                }
            }
        }
        .navigationTitle(country.name)
        .task {
            await viewModel.loadCities(for: country)
        }
    }

    private func retryRow(message: String, retry: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(message)
                .foregroundStyle(.secondary)
            Button("Повторить", action: retry)
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    NavigationStack {
        CityListView(
            country: Country(id: 1, code: "kz", name: "Казахстан"),
            viewModel: SettingsViewModel(),
            onCitySelected: {}
        )
    }
    .environmentObject(SelectedCityStore())
}
