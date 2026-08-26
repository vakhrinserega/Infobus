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

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(cityStore)
                .environmentObject(settingsStore)
                .preferredColorScheme(settingsStore.theme.colorScheme)
                .environment(\.locale, settingsStore.language.localeOverride ?? .autoupdatingCurrent)
        }
    }
}
