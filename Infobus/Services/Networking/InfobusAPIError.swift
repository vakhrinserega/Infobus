//
//  InfobusAPIError.swift
//  Infobus
//

import Foundation

enum InfobusAPIError: LocalizedError {
    case invalidURL
    case serverError(statusCode: Int)
    case decodingFailed(underlying: Error)
    case network(underlying: Error)
    /// The Apps Script appeals backend explicitly rejected a request —
    /// bad input, or (see the anti-spam limits added to Code.gs) this
    /// device over its cooldown or daily cap. `message` is already the
    /// exact, ready-to-show Russian sentence the server sent, not a
    /// generic one, so callers should prefer it outright over wrapping
    /// it in their own "Не удалось..." phrasing.
    case appealRejected(message: String)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Некорректный адрес запроса."
        case .serverError(let statusCode):
            return "Сервер вернул ошибку (\(statusCode))."
        case .decodingFailed:
            return "Неверный формат ответа сервера."
        case .network:
            return "Проблема с подключением к сети."
        case .appealRejected(let message):
            return message
        }
    }
}
