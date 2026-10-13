//
//  SettingsView.swift
//  Infobus
//
//  City selection (with cache status + manual refresh), accessible-bus
//  preference, location preference (with a way out if iOS itself denied
//  permission), appearance override, language override, and app info.
//  Refresh-interval settings are deliberately absent — buses poll on a fixed
//  short interval while a live screen is visible, and route/station data
//  refreshes on city selection and stale cold launch — neither is
//  user-configurable, per the discussion with the product owner.
//
//  This root screen keeps its own "Настройки" title bar (unlike the other
//  tabs, which go edge-to-edge) — a Form full of sections reads better with
//  a header naming the screen. The pushed CitySelectionView/CityListView
//  destinations below keep their own bar/back button as normal drill-down
//  screens either way.
//

import SwiftUI
import UIKit

struct SettingsView: View {
    @EnvironmentObject private var cityStore: SelectedCityStore
    @EnvironmentObject private var settings: AppSettingsStore
    @StateObject private var viewModel = SettingsViewModel()
    @StateObject private var locationAuthorization = LocationAuthorizationObserver()
    @State private var navigationPath = NavigationPath()

    var body: some View {
        NavigationStack(path: $navigationPath) {
            Form {
                citySection
                accessibleBusesSection
                locationSection
                appearanceSection
                languageSection
                aboutSection
            }
            .navigationTitle("Настройки")
            .navigationDestination(for: SettingsRoute.self) { route in
                switch route {
                case .citySelection:
                    CitySelectionView(viewModel: viewModel)
                case .cityList(let country):
                    CityListView(country: country, viewModel: viewModel) {
                        // Clearing the whole path (not just popping one level) is
                        // what lets picking a city land straight back on Settings,
                        // regardless of how many levels deep the picker pushed.
                        navigationPath = NavigationPath()
                    }
                }
            }
            .task {
                if let city = cityStore.selectedCity, let country = cityStore.selectedCountry {
                    await viewModel.loadCityDataInfo(city: city, country: country)
                }
                // Covers first launch, where `useMyLocation` already defaults to true and
                // .onChange below never fires since there's no on->on transition to catch.
                if settings.useMyLocation {
                    locationAuthorization.requestIfNeeded()
                }
            }
        }
    }

    // MARK: - Sections

    private var citySection: some View {
        Section {
            NavigationLink(value: SettingsRoute.citySelection) {
                HStack {
                    Text("Город")
                    Spacer()
                    if let city = cityStore.selectedCity {
                        Text(city.name)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Не выбран")
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if viewModel.isRefreshingCityData {
                HStack {
                    ProgressView()
                    Text("Обновляем маршруты и остановки…")
                        .foregroundStyle(.secondary)
                }
            } else if let error = viewModel.cityDataRefreshError {
                VStack(alignment: .leading, spacing: 6) {
                    // Same fix as elsewhere — `error` is a plain `String`
                    // set on the view model; `Text(String)` never localizes.
                    Text(LocalizedStringKey(error))
                        .foregroundStyle(.secondary)
                    Button("Повторить") {
                        viewModel.retryCityDataRefresh()
                    }
                }
            } else if cityStore.selectedCity != nil {
                HStack {
                    if let lastUpdated = viewModel.cityDataLastUpdated {
                        Text("Обновлено \(lastUpdated.formatted(.relative(presentation: .named)))")
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Обновить", action: refreshCurrentCity)
                }
            }
        } footer: {
            Text("Определяет, какие маршруты, остановки и автобусы показываются в приложении.")
        }
    }

    private var accessibleBusesSection: some View {
        Section {
            Toggle("Отмечать автобусы с пандусом", isOn: $settings.highlightAccessibleBuses)
        } footer: {
            Text("Показываются все автобусы; при включении оборудованные пандусом отмечаются отдельным значком.")
        }
    }

    private var locationSection: some View {
        Section {
            Toggle("Определять моё местоположение", isOn: $settings.useMyLocation)
                .onChange(of: settings.useMyLocation) { _, isOn in
                    if isOn { locationAuthorization.requestIfNeeded() }
                }

            if settings.useMyLocation && locationAuthorization.isDenied {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Геолокация отключена в системе")
                        .foregroundStyle(.secondary)
                    Button("Открыть Настройки", action: openSystemSettings)
                }
            }
        } footer: {
            Text("Используется, чтобы показать вас на карте и подсветить вашу остановку на схеме маршрута.")
        }
    }

    private var appearanceSection: some View {
        Section {
            Picker("Тема", selection: $settings.theme) {
                ForEach(AppTheme.allCases) { theme in
                    Text(theme.displayName).tag(theme)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    private var languageSection: some View {
        Section {
            Picker("Язык", selection: $settings.language) {
                ForEach(AppLanguage.allCases) { language in
                    Text(language.displayName).tag(language)
                }
            }
        }
    }

    private var aboutSection: some View {
        Section {
            if let url = feedbackMailURL {
                Link("Написать в поддержку", destination: url)
            }
            HStack {
                Text("Версия")
                Spacer()
                Text(appVersionString)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Actions

    private func refreshCurrentCity() {
        guard let city = cityStore.selectedCity, let country = cityStore.selectedCountry else { return }
        viewModel.manualRefresh(city: city, country: country)
    }

    private func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    // MARK: - Formatting

    private var feedbackMailURL: URL? {
        URL(string: "mailto:support@infobus.kz")
    }

    private var appVersionString: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
        return "\(version) (\(build))"
    }
}

#Preview {
    SettingsView()
        .environmentObject(SelectedCityStore())
        .environmentObject(AppSettingsStore())
}
