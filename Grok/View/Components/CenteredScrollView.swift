//
//  CenteredScrollView.swift
//  Grok
//
//  Created by Tricentric Labs on 01/10/2026.
//

import SwiftUI

/// Centres its content while there is room and scrolls once there isn't, so
/// the empty states keep their composition on a tall window without clipping
/// on a short one.
struct CenteredScrollView<Content: View>: View {
    /// Space reserved at the bottom for the floating composer.
    var bottomInset: CGFloat = 140
    @ViewBuilder let content: () -> Content

    var body: some View {
        GeometryReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                content()
                    .padding(.horizontal, 40)
                    .padding(.top, 24)
                    .padding(.bottom, bottomInset)
                    .frame(width: proxy.size.width, alignment: .center)
                    .frame(minHeight: proxy.size.height, alignment: .center)
            }
        }
    }
}
