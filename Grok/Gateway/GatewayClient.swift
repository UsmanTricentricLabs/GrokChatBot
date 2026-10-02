//
//  GatewayClient.swift
//  Grok
//
//  Created by Tricentric Labs on 01/10/2026.
//

import Foundation
import os

/// The single path from this app to any AI provider.
///
/// Every AI feature goes through here; nothing in the app talks to OpenAI,
/// Anthropic, Gemini or xAI directly, and no provider credentials exist in the
/// bundle. The Gateway picks the provider, holds the keys and meters usage.
actor GatewayClient {

    static let shared = GatewayClient()

    private let configuration: GatewayConfiguration
    private let session: URLSession
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(
        configuration: GatewayConfiguration = .shared,
        session: URLSession = .shared
    ) {
        self.configuration = configuration
        self.session = session
    }

    var chatModel: String { configuration.chatModel }
    var imageModel: String { configuration.imageModel }

    // MARK: Endpoints

    /// Sends a conversation and returns the assistant's reply.
    func chat(
        messages: [GatewayChatTurn],
        system: String? = nil,
        maxOutputTokens: Int? = nil,
        temperature: Double? = nil
    ) async throws -> GatewayChatResponse {
        let body = GatewayChatRequest(
            messages: messages,
            system: system,
            model: configuration.chatModel,
            maxOutputTokens: maxOutputTokens,
            temperature: temperature
        )
        return try await send(path: "/v1/ai/chat", body: body)
    }

    /// Generates an image, optionally from a reference image.
    func image(
        prompt: String,
        system: String? = nil,
        reference: GatewayImagePayload? = nil
    ) async throws -> GatewayImageResponse {
        let body = GatewayImageRequest(
            prompt: prompt,
            model: configuration.imageModel,
            system: system,
            image: reference
        )
        return try await send(path: "/v1/ai/image", body: body)
    }

    // MARK: Transport

    private func send<Body: Encodable, Response: Decodable>(
        path: String,
        body: Body
    ) async throws -> Response {
        var request = URLRequest(url: configuration.baseURL.appendingPathComponent(path))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(configuration.appId, forHTTPHeaderField: "X-App-Id")
        request.setValue(configuration.appKey, forHTTPHeaderField: "X-App-Key")
        request.setValue(GatewayUserIdentity.current, forHTTPHeaderField: "X-User-Id")
        request.httpBody = try encoder.encode(body)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch {
            GatewayError.log.error("Gateway transport failure: \(error.localizedDescription, privacy: .public)")
            throw GatewayError.network
        }

        try Task.checkCancellation()

        guard let http = response as? HTTPURLResponse else { throw GatewayError.network }

        guard (200..<300).contains(http.statusCode) else {
            throw GatewayError.make(
                status: http.statusCode,
                envelope: try? decoder.decode(GatewayErrorEnvelope.self, from: data),
                retryAfterHeader: Self.retryAfter(from: http)
            )
        }

        do {
            return try decoder.decode(Response.self, from: data)
        } catch {
            // A success status the app cannot read is still a developer
            // problem, so it is logged rather than shown.
            GatewayError.log.error("Gateway response could not be decoded: \(error.localizedDescription, privacy: .public)")
            throw GatewayError.temporary
        }
    }

    private static func retryAfter(from response: HTTPURLResponse) -> TimeInterval? {
        guard let value = response.value(forHTTPHeaderField: "Retry-After") else { return nil }
        return TimeInterval(value)
    }
}
