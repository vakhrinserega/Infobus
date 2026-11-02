//
//  ContentView.swift
//  Infobus
//
//  Root tab bar — five sections of the app. Карта comes first since it's
//  the primary, full-screen view of live buses. Уведомления sits dead
//  center (position 3 of 5) rather than Поиск — per direct feedback,
//  notifications wanted the more prominent middle slot.
//
//  Also where AnnouncementStore's and AppealsStore's polls are driven from
//  (the two `.task(id:)` blocks below) rather than from NotificationsView
//  itself — the unseen-badge on that tab's own icon needs to update while
//  some *other* tab is on screen, so the polls that feed it have to keep
//  running independently of which tab is actually visible. Two separate
//  `.task(id:)` blocks rather than one combined one — they're two
//  unrelated backends (see NotificationsView's header) with no reason to
//  share a restart/cancel lifecycle.
//

import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var cityStore: SelectedCityStore
    @EnvironmentObject private var announcementStore: AnnouncementStore
    @EnvironmentObject private var appealsStore: AppealsStore

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

            NotificationsView()
                .tabItem {
                    Label("Уведомления", systemImage: "bell")
                }
                .badge(notificationsBadgeCount)

            SearchView()
                .tabItem {
                    Label("Поиск", systemImage: "magnifyingglass")
                }

            SettingsView()
                .tabItem {
                    Label("Настройки", systemImage: "gearshape")
                }
        }
        .task(id: cityStore.selectionKey) {
            guard let city = cityStore.selectedCity else {
                announcementStore.clear()
                return
            }
            await announcementStore.run(for: city)
        }
        .task(id: cityStore.selectionKey) {
            guard let city = cityStore.selectedCity else {
                appealsStore.clear()
                return
            }
            await appealsStore.run(for: city)
        }
    }

    /// One announcement (at most) plus however many answered appeals the
    /// rider hasn't opened yet — two unrelated sources, one badge number.
    private var notificationsBadgeCount: Int {
        (announcementStore.hasUnseenAnnouncement ? 1 : 0) + appealsStore.unseenAnsweredCount
    }
}

#Preview {
    ContentView()
        .environmentObject(SelectedCityStore())
        .environmentObject(AppSettingsStore())
        .environmentObject(AnnouncementStore())
        .environmentObject(AppealsStore())
}
