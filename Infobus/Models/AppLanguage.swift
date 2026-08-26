//
//  AppLanguage.swift
//  Infobus
//
//  In-app language override, independent of the device's own language
//  setting. `.system` (the default) means no override — SwiftUI just uses
//  whatever locale the device is already set to. Only Russian exists as an
//  actual translation today; add a case here (plus its strings in
//  Localizable.xcstrings) whenever a new translation is ready — nothing
//  else needs to change.
//

import SwiftUI

enum AppLanguage: String, CaseIterable, Identifiable, Codable {
    case system
    case russian

    var id: String { rawValue }

    var displayName: LocalizedStringKey {
        switch self {
        case .system: "Системный"
        case .russian: "Русский"
        }
    }

    /// nil tells SwiftUI to defer to the device's own locale.
    var localeOverride: Locale? {
        switch self {
        case .system: nil
        case .russian: Locale(identifier: "ru")
        }
    }
}
