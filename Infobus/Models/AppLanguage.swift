//
//  AppLanguage.swift
//  Infobus
//
//  In-app language override, independent of the device's own language
//  setting. `.system` (the default) means no override — SwiftUI just uses
//  whatever locale the device is already set to.
//
//  Order matters here: `CaseIterable`'s `allCases` follows declaration
//  order, and that's exactly the order the Settings picker lists them in —
//  Системный, Казахский, Русский, Украинский, English.
//
//  Each case's `displayName` is deliberately NOT translated per active app
//  language in Localizable.xcstrings (except .system, which really is a
//  translatable label, not a language's own name) — a language's name
//  stays written in its own script no matter which language is currently
//  active, the same convention every other app's language picker uses.
//

import SwiftUI

enum AppLanguage: String, CaseIterable, Identifiable, Codable {
    case system
    case kazakh
    case russian
    case ukrainian
    case english

    var id: String { rawValue }

    var displayName: LocalizedStringKey {
        switch self {
        case .system: "Системный"
        case .kazakh: "Қазақша"
        case .russian: "Русский"
        case .ukrainian: "Українська"
        case .english: "English"
        }
    }

    /// nil tells SwiftUI to defer to the device's own locale.
    var localeOverride: Locale? {
        switch self {
        case .system: nil
        case .kazakh: Locale(identifier: "kk")
        case .russian: Locale(identifier: "ru")
        case .ukrainian: Locale(identifier: "uk")
        case .english: Locale(identifier: "en")
        }
    }
}
