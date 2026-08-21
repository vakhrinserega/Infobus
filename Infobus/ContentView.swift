//
//  ContentView.swift
//  Infobus
//
//  Root tab bar — five sections of the app.
//

import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView {
            RoutesListView()
                .tabItem {
                    Label("Маршруты", systemImage: "list.bullet")
                }

            MapView()
                .tabItem {
                    Label("Карта", systemImage: "map")
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
}
