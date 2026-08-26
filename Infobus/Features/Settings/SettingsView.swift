//
//  SettingsView.swift
//  Infobus
//
//  City selection, accessible-bus preferences, location preference, and app
//  info. Refresh-interval settings are deliberately absent — buses poll on a
//  fixed short interval while a live screen is visible, and route/station
//  data refreshes on city selection and stale cold launch — neither is
//  user-configurable, per the discussion with the product owner.
//

import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var cityStore: SelectedCityStore
    @EnvironmentObject private var settings: AppSettingsStore
    @StateObject private var viewModel = SettingsViewModel()

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    NavigationLink {
                        CitySelectionView(viewModel: viewModel)
                    } label: {
                        HStack {
                            Text("Город")
                            Spacer()
                            Text(cityStore.selectedCity?.name ?? "Не выбран")
                                .foregroundStyle(.secondary)
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
                            Text(error)
                                .foregroundStyle(.secondary)
                            Button("Повторить") {
                                viewModel.retryCityDataRefresh()
                            }
                        }
                    }
                } footer: {
                    Text("Определяет, какие маршруты, остановки и автобусы показываются в приложении.")
                }

                Section {
                    Toggle("Отмечать автобусы с пандусом", isOn: $settings.highlightAccessibleBuses)
                } footer: {
                    Text("Показываются все автобусы; при включении оборудованные пандусом отмечаются отдельным значком.")
                }

                Section {
                    Toggle("Определять моё местоположение", isOn: $settings.useMyLocation)
                } footer: {
                    Text("Используется, чтобы показать вас на карте и подсветить вашу остановку на схеме маршрута.")
                }

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
            .navigationTitle("Настройки")
        }
    }

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
