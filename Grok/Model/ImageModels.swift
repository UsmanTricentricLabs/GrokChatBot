//
//  ImageModels.swift
//  Grok
//
//  Created by Tricentric Labs on 01/10/2026.
//

import AppKit
import Foundation

/// The eight styles offered by the popover that opens from the style pill.
nonisolated enum ImageStyle: String, CaseIterable, Identifiable, Hashable {
    case photographic = "Photographic"
    case cinematic = "Cinematic"
    case illustration = "Illustration"
    case anime = "Anime"
    case render3D = "3D Render"
    case watercolor = "Watercolor"
    case sketch = "Sketch"
    case minimal = "Minimal"

    var id: String { rawValue }
    var title: String { rawValue }

    var symbol: String {
        switch self {
        case .photographic: return "camera"
        case .cinematic: return "film"
        case .illustration: return "paintbrush"
        case .anime: return "wand.and.stars"
        case .render3D: return "cube"
        case .watercolor: return "drop"
        case .sketch: return "pencil.tip"
        case .minimal: return "square"
        }
    }
}

nonisolated enum ImageAspectRatio: String, CaseIterable, Identifiable, Hashable {
    case square = "1:1"
    case classic = "4:3"
    case wide = "16:9"
    case tall = "9:16"

    var id: String { rawValue }
    var title: String { rawValue }

    var value: CGFloat {
        switch self {
        case .square: return 1
        case .classic: return 4.0 / 3.0
        case .wide: return 16.0 / 9.0
        case .tall: return 9.0 / 16.0
        }
    }
}

nonisolated enum GeneratedImageState: Equatable {
    case generating
    case ready
    case failed(AIErrorPresentation)
}

struct GeneratedImage: Identifiable, Equatable {
    let id: UUID
    var prompt: String
    var style: ImageStyle
    var ratio: ImageAspectRatio
    var state: GeneratedImageState
    var createdAt: Date
    /// The artwork returned by the Gateway, decoded once on arrival.
    var image: NSImage?

    init(
        id: UUID = UUID(),
        prompt: String,
        style: ImageStyle,
        ratio: ImageAspectRatio,
        state: GeneratedImageState = .generating,
        createdAt: Date = Date(),
        image: NSImage? = nil
    ) {
        self.id = id
        self.prompt = prompt
        self.style = style
        self.ratio = ratio
        self.state = state
        self.createdAt = createdAt
        self.image = image
    }

    /// "Cinematic · 16:9", the caption shown under a finished image and inside
    /// the style pill.
    var styleCaption: String { "\(style.title) · \(ratio.title)" }
}

/// A day's worth of images, as the gallery groups them.
struct ImageGroup: Identifiable {
    let id = UUID()
    let label: String
    let images: [GeneratedImage]
}
