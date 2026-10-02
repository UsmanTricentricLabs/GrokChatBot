//
//  GatewayConfiguration.swift
//  Grok
//
//  Created by Tricentric Labs on 01/10/2026.
//

import Foundation

/// Connection details for the Central AI Gateway, read from
/// `GatewayConfig.plist` so the app credential lives in configuration rather
/// than scattered through the source.
///
/// The app key identifies this app to the Gateway. It is not a provider
/// secret — no provider credentials exist anywhere in this app, because every
/// AI request is routed through the Gateway, which holds them.
nonisolated struct GatewayConfiguration {
    let baseURL: URL
    let appId: String
    let appKey: String
    /// Model used for every text feature: chat, PDF follow-ups and summaries.
    let chatModel: String
    /// Model used for image generation.
    let imageModel: String

    static let shared: GatewayConfiguration = {
        guard
            let url = Bundle.main.url(forResource: "GatewayConfig", withExtension: "plist"),
            let data = try? Data(contentsOf: url),
            let values = try? PropertyListDecoder().decode(Values.self, from: data),
            let baseURL = URL(string: values.baseURL)
        else {
            // A missing or malformed config means no AI feature can work, so
            // fail loudly during development rather than at the first request.
            fatalError("GatewayConfig.plist is missing or malformed.")
        }

        return GatewayConfiguration(
            baseURL: baseURL,
            appId: values.appId,
            appKey: values.appKey,
            chatModel: values.chatModel,
            imageModel: values.imageModel
        )
    }()

    private struct Values: Decodable {
        let baseURL: String
        let appId: String
        let appKey: String
        let chatModel: String
        let imageModel: String

        private enum CodingKeys: String, CodingKey {
            case baseURL = "BaseURL"
            case appId = "AppId"
            case appKey = "AppKey"
            case chatModel = "ChatModel"
            case imageModel = "ImageModel"
        }
    }
}
