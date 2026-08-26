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
        }
    }
}
