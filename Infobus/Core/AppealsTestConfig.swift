//
//  AppealsTestConfig.swift
//  Infobus
//
//  TEMPORARY, for testing only. The real plan is for the infobus.kz
//  backend to return `appealsEndpoint` inside `/api/cities/{id}` (see
//  CityInfo.swift) — that way the Apps Script URL can change without an
//  app update. Until that backend change is actually made, there's no
//  way to get the URL into the app except hardcoding it, so this file is
//  that hardcode point: it's the ONLY file to edit to try "Обращения"
//  end-to-end before the server side exists.
//
//  How to fill this in: create the Apps Script project from the Code.gs
//  delivered earlier, finish its one-time setup (bot token, chat id,
//  `setup()`, Deploy → Web app), and paste the resulting ".../exec" URL
//  below.
//
//  AppealsStore checks `CityInfo.appealsEndpoint` FIRST and only falls
//  back to this value when the server doesn't supply one — so the day
//  infobus.kz starts returning `appealsEndpoint` for real, it takes over
//  automatically and this file can simply be deleted (along with the one
//  `??`/fallback line in AppealsStore.resolveEndpoint that reads it).
//

import Foundation

enum AppealsTestConfig {
    /// Paste your Apps Script Web App URL here, e.g.
    /// "https://script.google.com/macros/s/AKfycb.../exec".
    /// Leave `nil` (or empty) to disable the override entirely.
    static let hardcodedEndpoint: String? = "https://script.google.com/macros/s/AKfycbxQSY5rhsNsJB5VJz8TTVS0jwYsXYT2PrkY3LPyvEEN8x6HzRyGHKkOR76tUvN8chz5oA/exec"
}
