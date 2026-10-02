//
//  ImageGenerationService.swift
//  Grok
//
//  Created by Tricentric Labs on 01/10/2026.
//

import AppKit
import os

nonisolated protocol ImageGenerationService {
    /// Produces an image for the prompt, optionally guided by a reference.
    func generate(
        prompt: String,
        style: ImageStyle,
        ratio: ImageAspectRatio,
        reference: NSImage?
    ) async throws -> Data
}

/// Routes image generation through the Central AI Gateway.
///
/// The Gateway's image endpoint takes a prompt and an optional reference
/// image. Style and aspect ratio are not request fields, so the app folds the
/// user's choices into the prompt text, which keeps the existing picker
/// working without sending fields the Gateway rejects.
nonisolated struct GatewayImageGenerationService: ImageGenerationService {

    private let client: GatewayClient

    init(client: GatewayClient = .shared) {
        self.client = client
    }

    func generate(
        prompt: String,
        style: ImageStyle,
        ratio: ImageAspectRatio,
        reference: NSImage?
    ) async throws -> Data {
        let response = try await client.image(
            prompt: Self.compose(prompt: prompt, style: style, ratio: ratio),
            reference: reference.flatMap(Self.payload)
        )
        try Task.checkCancellation()

        guard let data = Data(base64Encoded: response.image.data, options: .ignoreUnknownCharacters),
              !data.isEmpty
        else {
            GatewayError.log.error("Gateway image could not be decoded. request_id=\(response.requestId, privacy: .public)")
            throw GatewayError.temporary
        }
        return data
    }

    /// Carries the style and aspect ratio in the prompt, since the endpoint
    /// accepts neither as a field.
    private static func compose(prompt: String, style: ImageStyle, ratio: ImageAspectRatio) -> String {
        "\(prompt)\n\nStyle: \(style.title). Aspect ratio: \(ratio.title)."
    }

    private static func payload(for image: NSImage) -> GatewayImagePayload? {
        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:])
        else { return nil }

        return GatewayImagePayload(data: png.base64EncodedString(), mimeType: "image/png")
    }
}
