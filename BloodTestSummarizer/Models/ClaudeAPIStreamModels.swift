//
//  ClaudeAPIStreamModels.swift
//  BloodTestSummarizer
//
//  Created by Parth Garg on 29/08/26.
//

import Foundation

/// A single Server-Sent Event payload from the streaming Messages API.
///
/// We only care about a handful of the documented event types
/// (`content_block_delta` for incremental text, `message_delta` for the
/// final `stop_reason`, and `error`), so this is deliberately loose rather
/// than a full enum over every event shape.
/// See https://docs.claude.com/en/docs/build-with-claude/streaming
struct StreamChunk: Decodable, Sendable {
    let type: String
    let delta: Delta?
    let error: APIErrorBody.Detail?

    struct Delta: Decodable, Sendable {
        let text: String?
        let stopReason: String?

        enum CodingKeys: String, CodingKey {
            case text
            case stopReason = "stop_reason"
        }
    }
}
