//
//  ClaudeAPIResponseModels.swift
//  BloodTestSummarizer
//
//  Created by Parth Garg on 29/08/26.
//

import Foundation

// MARK: - Error body

/// Anthropic returns `{"type": "error", "error": {"type": ..., "message": ...}}`
/// on non-2xx responses. We decode just enough of it for a readable message.
struct APIErrorBody: Decodable, Sendable {
    struct Detail: Decodable, Sendable {
        let type: String
        let message: String
    }
    let error: Detail
}

