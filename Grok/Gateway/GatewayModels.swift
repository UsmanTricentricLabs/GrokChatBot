//
//  GatewayModels.swift
//  Grok
//
//  Created by Tricentric Labs on 01/10/2026.
//

import Foundation

// MARK: Chat

nonisolated struct GatewayChatTurn: Encodable {
    enum Role: String, Encodable {
        case user
        case assistant
    }

    let role: Role
    let content: String
}

nonisolated struct GatewayChatRequest: Encodable {
    let messages: [GatewayChatTurn]
    let system: String?
    let model: String
    let maxOutputTokens: Int?
    let temperature: Double?

    private enum CodingKeys: String, CodingKey {
        case messages, system, model, temperature
        case maxOutputTokens = "max_output_tokens"
    }
}

nonisolated struct GatewayChatResponse: Decodable {
    struct Message: Decodable {
        let role: String
        let content: String
    }

    let requestId: String
    let model: String
    let message: Message

    private enum CodingKeys: String, CodingKey {
        case model, message
        case requestId = "request_id"
    }
}

// MARK: Image

nonisolated struct GatewayImagePayload: Codable {
    let data: String
    let mimeType: String

    private enum CodingKeys: String, CodingKey {
        case data
        case mimeType = "mime_type"
    }
}

nonisolated struct GatewayImageRequest: Encodable {
    let prompt: String
    let model: String
    let system: String?
    /// An optional reference image for edit-style requests.
    let image: GatewayImagePayload?
}

nonisolated struct GatewayImageResponse: Decodable {
    let requestId: String
    let model: String
    let image: GatewayImagePayload

    private enum CodingKeys: String, CodingKey {
        case model, image
        case requestId = "request_id"
    }
}
