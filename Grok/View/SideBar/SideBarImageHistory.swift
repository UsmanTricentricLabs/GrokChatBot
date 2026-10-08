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
                Text("sidebar.section.images".localized)
                    .grokText(.label, color: GrokColor.sidebarInk)
                Spacer(minLength: 0)
                Button {
                    imageVM.isGalleryPresented = true
                } label: {
                    Text("common.seeAll".localized)
                        .grokText(.labelPlain, color: GrokColor.sidebarMutedInk)
                }
                .buttonStyle(GrokButtonStyle())
            }
            .frame(height: 24)

            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(imageVM.images) { image in
                    SideBarImageThumbnail(
                        image: image,
                        isSelected: image.id == imageVM.latestImage?.id,
                        action: { imageVM.select(image) },
                        onDelete: { imageVM.delete(image) }
                    )
                }
            }
        }
    }
}

private struct SideBarImageThumbnail: View {
    let image: GeneratedImage
    let isSelected: Bool
    let action: () -> Void
    let onDelete: () -> Void

    @State private var isHovering = false

    var body: some View {
        thumbnail
            // A thumbnail is too small for a "⋯" button, so the delete badge
            // appears on hover instead — and right-click does the same, which
            // is what the Finder habit reaches for.
            .overlay(alignment: .topTrailing) {
                if isHovering, image.state != .generating {
                    deleteBadge
                }
            }
            .contextMenu {
                Button("common.delete".localized, role: .destructive, action: onDelete)
            }
            .onHover { isHovering = $0 }
            .animation(.easeOut(duration: 0.12), value: isHovering)
    }

    private var deleteBadge: some View {
        Button(action: onDelete) {
            ZStack {
                Circle().fill(GrokColor.black1.opacity(0.75))
                SymbolIcon("xmark", size: 9, weight: .bold, color: GrokColor.white1)
            }
            .frame(width: 20, height: 20)
        }
        .buttonStyle(GrokButtonStyle())
        .padding(5)
        .help("sidebar.deleteImage".localized)
    }

    private var thumbnail: some View {
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
