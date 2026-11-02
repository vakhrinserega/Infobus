//
//  InfobusApp.swift
//  Infobus
//
//  Created by Mag on 21.08.2026.
//

import SwiftUI

@main
struct InfobusApp: App {
    @StateObject private var cityStore = SelectedCityStore()
    @StateObject private var settingsStore = AppSettingsStore()
    @StateObject private var announcementStore = AnnouncementStore()
    @StateObject private var appealsStore = AppealsStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(cityStore)
                .environmentObject(settingsStore)
                .environmentObject(announcementStore)
                .environmentObject(appealsStore)
                .preferredColorScheme(settingsStore.theme.colorScheme)
                .environment(\.locale, settingsStore.language.localeOverride ?? .autoupdatingCurrent)
        }
    }
}
