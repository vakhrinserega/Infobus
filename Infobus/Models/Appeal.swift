//
//  Appeal.swift
//  Infobus
//
//  A rider's own support request ("обращение") — one message, at most one
//  reply, never a back-and-forth thread (see AppealsStore's header for
//  why that scope cut is deliberate). Comes from a per-city Google Apps
//  Script Web App (`CityInfo.appealsEndpoint`), not the main infobus.kz
//  routing backend — a separate, much lighter-weight system (a form, a
//  spreadsheet, a Telegram bot relaying replies) that just happens to
//  speak JSON over HTTP the same way the rest of this client expects.
//
//  `category` is modeled but not yet exposed in the compose UI — plumbed
//  through end to end now so it costs nothing to turn on a picker later
//  without touching the network layer again.
//

import Foundation

enum AppealStatus: String, Decodable {
    case new
    case answered
}

struct Appeal: Decodable, Identifiable {
    let id: Int
    let message: String
    let category: String?
    let status: AppealStatus
    let answer: String?
    let createdAt: Date
    let answeredAt: Date?
}
