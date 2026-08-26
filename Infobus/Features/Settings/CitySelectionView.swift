//
//  CitySelectionView.swift
//  Infobus
//
//  Two-step picker pushed from Settings: country, then city. Kept as its own
//  screen rather than a flat list since the API itself is scoped that way
//  (cities only ever come back per-country).
//

import SwiftUI

struct CitySelectionView: View {
    @EnvironmentObject private var cityStore: SelectedCityStore
    @ObservedObject var viewModel: SettingsViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            switch viewModel.countriesState {
            case .idle, .loading:
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
            case .failed(let message):
                retryRow(message: message) {
                    Task { await viewModel.loadCountries() }
                }
            case .loaded(let countries):
                ForEach(countries) { country in
                    NavigationLink(country.name) {
                        cityList(for: country)
                    }
                }
            }
        }
        .navigationTitle("Страна")
        .task {
            if case .idle = viewModel.countriesState {
                await viewModel.loadCountries()
            }
        }
    }

    @ViewBuilder
    private func cityList(for country: Country) -> some View {
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
                        dismiss()
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
        CitySelectionView(viewModel: SettingsViewModel())
    }
    .environmentObject(SelectedCityStore())
}
