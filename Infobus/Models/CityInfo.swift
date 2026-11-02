//
//  CityInfo.swift
//  Infobus
//
//  GET {serviceURL}/api/cities/{id}
//  City-level metadata: map framing and an optional city-wide announcement.
//

import Foundation

struct CityInfo: Decodable {
    let id: Int
    let name: String
    let lat: Double
    let lon: Double
    let mapZoom: Int
    let mapLayers: [String]
    let message: String
    let displayMessage: Bool
    /// Web App URL of this city's support-appeals backend (Google Apps
    /// Script + a spreadsheet + a Telegram bot relaying replies — see
    /// AppealsStore's header). Absent/nil for a city that hasn't been set
    /// up yet, in which case "Обращения" just says it isn't available
    /// there rather than offering a form that would go nowhere.
    ///
    /// Deliberately server-delivered rather than hardcoded in the app:
    /// the script/sheet behind this URL can be rewritten or swapped out
    /// freely as long as it keeps speaking the same JSON contract, and
    /// even the URL itself can change (a new Apps Script deployment) with
    /// nothing more than an edit here on the server — no app update, no
    /// App Store review, since every install just reads whatever this
    /// field says on its next poll.
    let appealsEndpoint: String?
}
