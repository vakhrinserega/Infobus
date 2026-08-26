//
//  AppTheme.swift
//  Infobus
//
//  Explicit appearance override for Settings. `.system` (the default) means
//  no override at all — the app just follows the device's own setting.
//

import SwiftUI

enum AppTheme: String, CaseIterable, Identifiable, Codable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var displayName: LocalizedStringKey {
        switch self {
        case .system: "Системная"
        case .light: "Светлая"
        case .dark: "Тёмная"
        }
    }

    /// nil tells SwiftUI to defer to the system appearance.
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}
