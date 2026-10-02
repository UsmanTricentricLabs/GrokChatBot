//
//  GeneratedImageView.swift
//  Grok
//
//  Created by Tricentric Labs on 01/10/2026.
//

import SwiftUI

/// Draws a generated image, or a neutral plate while one is still on its way.
struct GeneratedImageView: View {
    let image: GeneratedImage
    var contentMode: ContentMode = .fit

    var body: some View {
        if let artwork = image.image {
            Image(nsImage: artwork)
                .resizable()
                .aspectRatio(contentMode: contentMode)
        } else {
            GrokColor.white4
        }
    }
}
