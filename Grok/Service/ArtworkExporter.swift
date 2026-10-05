//
//  ArtworkExporter.swift
//  Grok
//
//  Created by Tricentric Labs on 01/10/2026.
//

import AppKit

nonisolated enum ArtworkExportError: LocalizedError, Equatable {
    case encodingFailed

    var errorDescription: String? { "The image could not be exported." }
}

/// Writes a generated image to disk as PNG — used by the Save action on an
/// image result.
nonisolated enum ArtworkExporter {
    static func writePNG(_ image: NSImage, to url: URL) throws {
        guard let data = pngData(image) else { throw ArtworkExportError.encodingFailed }
        try data.write(to: url)
    }

    /// The same PNG encoding, for the history store — which keeps the bytes
    /// rather than writing them to a file the user chose.
    static func pngData(_ image: NSImage) -> Data? {
        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff)
        else { return nil }
        return bitmap.representation(using: .png, properties: [:])
    }
}
