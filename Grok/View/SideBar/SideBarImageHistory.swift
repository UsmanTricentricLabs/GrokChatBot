//
//  SideBarImageHistory.swift
//  Grok
//
//  Created by Tricentric Labs on 01/10/2026.
//

import SwiftUI

/// The image slot of the sidebar: a two-column thumbnail grid with "See all"
/// opening the full gallery.
struct SideBarImageHistory: View {
    @ObservedObject var imageVM: ImageViewModel

    private let columns = [
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 0) {
                Text("Images")
                    .grokText(.label, color: GrokColor.sidebarInk)
                Spacer(minLength: 0)
                Button {
                    imageVM.isGalleryPresented = true
                } label: {
                    Text("See all")
                        .grokText(.labelPlain, color: GrokColor.sidebarMutedInk)
                }
                .buttonStyle(GrokButtonStyle())
            }
            .frame(height: 24)

            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(imageVM.images) { image in
                    SideBarImageThumbnail(
                        image: image,
                        isSelected: image.id == imageVM.latestImage?.id
                    ) {
                        imageVM.select(image)
                    }
                }
            }
        }
    }
}

private struct SideBarImageThumbnail: View {
    let image: GeneratedImage
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                if image.state == .generating {
                    GrokColor.sidebarSelection
                    GrokSpinner(size: 22, color: GrokColor.sidebarMutedInk)
                } else {
                    GeneratedImageView(image: image, contentMode: .fill)
                }
            }
            .aspectRatio(1, contentMode: .fill)
            .clipShape(RoundedRectangle(cornerRadius: GrokMetrics.chipRadius, style: .continuous))
            .decorativeBorder(
                isSelected ? Color.white : .clear,
                width: 2,
                cornerRadius: GrokMetrics.chipRadius
            )
        }
        .buttonStyle(GrokButtonStyle())
        .help(image.prompt)
    }
}
