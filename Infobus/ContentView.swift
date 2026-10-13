//
//  ContentView.swift
//  Infobus
//
//  Root tab bar — five sections of the app. Карта comes first since it's
//  the primary, full-screen view of live buses.
//

import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView {
            MapView()
                .tabItem {
                    Label("Карта", systemImage: "map")
                }

            RoutesListView()
                .tabItem {
                    Label("Маршруты", systemImage: "list.bullet")
                }

            SearchView()
                .tabItem {
                    Label("Поиск", systemImage: "magnifyingglass")
                }

            NotificationsView()
                .tabItem {
                    Label("Уведомления", systemImage: "bell")
                }

            SettingsView()
                .tabItem {
                    Label("Настройки", systemImage: "gearshape")
                }
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(SelectedCityStore())
        .environmentObject(AppSettingsStore())
}
