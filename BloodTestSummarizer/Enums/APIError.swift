//
//  APIError.swift
//  BloodTestSummarizer
//
//  Created by Parth Garg on 29/08/26.
//

import Foundation

enum APIError: Error, LocalizedError, Sendable {
    case missingAPIKey
    case fileTooLarge
    case invalidResponse
    case server(String)
    case decoding(Error)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "No API key is configured. See README.md — for a shipping app, point this at your own backend instead."
        case .fileTooLarge:
            return "This PDF is over the 32MB request limit. Try a smaller file."
        case .invalidResponse:
            return "The server sent back something this app didn't expect."
        case .server(let message):
            return message
        case .decoding(let error):
            return "Couldn't parse the summary Claude returned: \(error.localizedDescription)"
        }
    }
}
