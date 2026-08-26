//
//  CitySelectionView.swift
//  Infobus
//
//  First step of the city picker: country list. Pushes a further
//  SettingsRoute.cityList(country) value rather than an embedded destination
//  closure, so both push levels share one NavigationPath owned by
//  SettingsView — required for picking a city to clear the whole path at
//  once (see SettingsRoute's header comment).
//

import SwiftUI

struct CitySelectionView: View {
    @ObservedObject var viewModel: SettingsViewModel

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
                    NavigationLink(value: SettingsRoute.cityList(country)) {
                        Text(country.name)
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
}
