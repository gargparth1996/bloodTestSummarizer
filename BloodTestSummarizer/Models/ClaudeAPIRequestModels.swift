//
//  ClaudeAPIError.swift
//  BloodTestSummarizer
//
//  Created by Parth Garg on 29/08/26.
//

import Foundation

struct MessagesRequest: Encodable, Sendable {
    let model: String
    let maxTokens: Int
    let system: String
    let messages: [APIMessage]

    enum CodingKeys: String, CodingKey {
        case model, system, messages
        case maxTokens = "max_tokens"
    }
}

struct APIMessage: Encodable, Sendable {
    let role: String
    let content: [RequestContentBlock]
}

/// A single block of message content sent to the Messages API.
///
/// Anthropic's PDF support expects a `document` block with a base64-encoded
/// `source`, sitting alongside a plain `text` block in the same message.
/// See https://docs.claude.com/en/docs/build-with-claude/pdf-support
enum RequestContentBlock: Encodable, Sendable {
    case text(String)
    case document(mediaType: String, base64Data: String)

    private enum CodingKeys: String, CodingKey {
        case type, text, source
    }

    private enum SourceCodingKeys: String, CodingKey {
        case type, data
        case mediaType = "media_type"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .text(let value):
            try container.encode("text", forKey: .type)
            try container.encode(value, forKey: .text)

        case .document(let mediaType, let base64Data):
            try container.encode("document", forKey: .type)
            var source = container.nestedContainer(keyedBy: SourceCodingKeys.self, forKey: .source)
            try source.encode("base64", forKey: .type)
            try source.encode(mediaType, forKey: .mediaType)
            try source.encode(base64Data, forKey: .data)
        }
    }
}
