//
//  ImageGalleryView.swift
//  Grok
//
//  Created by Tricentric Labs on 01/10/2026.
//

import SwiftUI

/// The full image history, grouped by day. Opened by "See all" in the sidebar.
struct ImageGalleryView: View {
    @ObservedObject var imageVM: ImageViewModel
    let availableWidth: CGFloat

    private var columns: [GridItem] {
        let count = max(2, min(4, Int((availableWidth - 40) / 243)))
        return Array(repeating: GridItem(.flexible(), spacing: 12), count: count)
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: true) {
            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("image.gallery.title".localized)
                            .grokText(.sectionTitle, color: GrokColor.black1)
                        Text("\(imageVM.groupedImages.reduce(0) { $0 + $1.images.count }) images")
                            .grokText(.caption, color: GrokColor.black6)
                    }
                    Spacer(minLength: 12)
                    // The gallery returns to the Create Image flow, so the
                    // control says where it goes rather than "Done".
                    PillButton(
                        title: "common.moveBack".localized,
                        height: 36,
                        background: GrokColor.white4,
                        hoverBackground: GrokColor.white2
                    ) {
                        imageVM.isGalleryPresented = false
                    }
                }

                ForEach(imageVM.groupedImages) { group in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(group.label)
                            .grokText(.label, color: GrokColor.black6)

                        LazyVGrid(columns: columns, spacing: 12) {
                            ForEach(group.images) { image in
                                Button {
                                    imageVM.select(image)
                                } label: {
                                    GeneratedImageView(image: image, contentMode: .fill)
                                        .aspectRatio(1, contentMode: .fill)
                                        .clipShape(
                                            RoundedRectangle(
                                                cornerRadius: GrokMetrics.tileRadius,
                                                style: .continuous
                                            )
                                        )
                                }
                                .buttonStyle(GrokButtonStyle())
                                .help(image.prompt)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, GrokMetrics.contentPadding)
            .padding(.vertical, 16)
        }
    }
}
