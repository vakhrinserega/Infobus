//
//  Prediction.swift
//  Infobus
//
//  GET {serviceURL}/cities/{id}/stations/{stationId}/prediction
//
//  Confirmed against the old Objective-C client's own display code
//  (PredictionTableViewDataSource.m) — despite this codebase initially
//  assuming minutes, the wire value is always in SECONDS. The old app
//  itself converts: over a minute away, show whole minutes (seconds / 60,
//  truncated); under a minute, show the raw seconds. `displayText` below
//  mirrors that exactly.
//

import Foundation

struct Prediction: Decodable, Identifiable {
    var id: Int { routeId }
    let routeId: Int
    /// Raw wire value, in SECONDS — use `displayText` rather than this
    /// directly for anything user-facing.
    let prediction: Double

    /// Human-readable arrival estimate, converted from seconds the same way
    /// the old app's own UI code did.
    ///
    /// Takes an explicit `locale` (rather than just interpolating "мин"/
    /// "сек" into a plain `String` the way this used to work) so the unit
    /// actually translates under the app's own in-app language override —
    /// `String(localized:)` without an explicit locale falls back to the
    /// system locale, which isn't necessarily the same thing here. The
    /// caller (StationPredictionSheet) reads its `locale` from the SwiftUI
    /// environment, which DOES follow that override.
    func displayText(locale: Locale) -> String {
        let totalSeconds = Int(prediction.rounded())
        if totalSeconds > 60 {
            return String(localized: "\(totalSeconds / 60) мин", locale: locale)
        } else {
            return String(localized: "\(totalSeconds) сек", locale: locale)
        }
    }
}
