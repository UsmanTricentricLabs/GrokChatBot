//
//  SideBarBackground.swift
//  Grok
//
//  Created by Tricentric Labs on 01/10/2026.
//

import SwiftUI

/// The sidebar plate: a flat grey with the starfield composited over it in
/// luminosity, which is how the design file builds it.
struct SideBarBackground: View {
    var body: some View {
        GrokColor.sidebarBase
            .overlay(
                Image(GrokAsset.sidebarBackground)
                    .resizable()
                    .scaledToFill()
                    .opacity(0.6)
                    .blendMode(.luminosity)
            )
            .compositingGroup()
            .clipped()
            .ignoresSafeArea()
    }
}
