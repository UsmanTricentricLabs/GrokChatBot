//
//  ImageScreen.swift
//  Grok
//
//  Created by Tricentric Labs on 01/10/2026.
//

import SwiftUI

/// The AI Image flow: prompt starters, style popover, generation and result.
struct ImageScreen: View {

    @ObservedObject var screenSwitchVM: ScreenSwitchViewModel
    @ObservedObject var imageVM: ImageViewModel
    var containerWidth: CGFloat
    var containerHeight: CGFloat
    var showsSidebarToggle: Bool = false

    private static let starters = [
        SuggestionStarter(
            title: "Product Shot",
            description: "Studio-lit objects on clean, simple backdrops",
            icon: .symbol("camera"),
            prompt: "A ceramic coffee cup on a seamless backdrop, studio lighting, soft shadows"
        ),
        SuggestionStarter(
            title: "Poster & Cover",
            description: "Bold compositions for posters and album art",
            icon: .symbol("rectangle.portrait"),
            prompt: "A bold typographic poster for an indie music festival at sunset"
        ),
        SuggestionStarter(
            title: "Scenes & Worlds",
            description: "Landscapes, interiors, and imagined places",
            icon: .symbol("photo"),
            prompt: "A lighthouse on a rocky cliff at dusk, waves crashing below, warm light glowing from the lamp"
        )
    ]

    var body: some View {
        VStack(spacing: 0) {
            HeaderBar(showsSidebarToggle: showsSidebarToggle) {
                screenSwitchVM.isSidebarPresented.toggle()
            }

            ZStack(alignment: .bottom) {
                content

                if !imageVM.isGalleryPresented {
                    PromptInputBarContainer {
                        PromptInputBar(
                            text: $imageVM.prompt,
                            placeholder: promptPlaceholder,
                            onSubmit: imageVM.generate
                        ) {
                            HStack(spacing: 6) {
                                stylePill
                                generateButton
                            }
                        }
                    }
                }
            }
        }
        .background(GrokColor.white3)
    }

    // MARK: Slots

    @ViewBuilder
    private var content: some View {
        if imageVM.isGalleryPresented {
            ImageGalleryView(imageVM: imageVM, availableWidth: containerWidth)
        } else if imageVM.threadImages.isEmpty {
            emptyState
        } else {
            resultThread
        }
    }

    private var emptyState: some View {
        CenteredScrollView {
            VStack(spacing: isCompact ? 32 : 60) {
                HeroHeader(
                    title: "What will you create?",
                    subtitle: "Describe an image, pick a style, and Grok brings it to life",
                    isCompact: isCompact
                )

                SuggestionRow(starters: Self.starters, availableWidth: containerWidth - 80) { starter in
                    imageVM.prompt = starter.prompt
                }
            }
        }
    }

    /// Short windows tighten the hero so it stays clear of the composer.
    private var isCompact: Bool {
        containerHeight < 700
    }

    /// Every image made in this session, in order — generating again adds a
    /// turn here rather than replacing what is on screen.
    private var resultThread: some View {
        ScrollViewReader { scroller in
            ScrollView(.vertical, showsIndicators: true) {
                VStack(alignment: .trailing, spacing: 24) {
                    ForEach(imageVM.threadImages) { image in
                        resultTurn(for: image)
                            .id(image.id)
                    }
                    Color.clear
                        .frame(height: 1)
                        .id(Self.threadBottomID)
                }
                .padding(.horizontal, GrokMetrics.contentPadding)
                .padding(.top, 16)
                .padding(.bottom, 136)
            }
            .onChange(of: imageVM.threadImages) { _ in
                withAnimation(.easeOut(duration: 0.2)) {
                    scroller.scrollTo(Self.threadBottomID, anchor: .bottom)
                }
            }
        }
    }

    private func resultTurn(for image: GeneratedImage) -> some View {
        VStack(alignment: .trailing, spacing: 16) {
            UserMessageBubble(text: image.prompt)
                .frame(maxWidth: .infinity, alignment: .trailing)

            Group {
                switch image.state {
                case .generating:
                    ImageGeneratingView(image: image)
                case .ready:
                    ImageResultView(image: image, imageVM: imageVM)
                case .failed(let failure):
                    ErrorAnswerView(failure: failure) {
                        imageVM.regenerate(image)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private static let threadBottomID = "image-thread-bottom"

    // MARK: Composer actions

    private var promptPlaceholder: String {
        imageVM.latestImage == nil
            ? "Describe the image you want to create..."
            : "Describe changes, or a new image..."
    }

    private var stylePill: some View {
        Button {
            imageVM.isStylePopoverPresented.toggle()
        } label: {
            HStack(spacing: 6) {
                SymbolIcon("paintpalette", size: 16, color: GrokColor.black1)
                Text(imageVM.styleCaption)
                    .grokText(.controlCompact, color: GrokColor.black1)
                    .fixedSize()
                SymbolIcon(
                    imageVM.isStylePopoverPresented ? "chevron.up" : "chevron.down",
                    size: 13,
                    color: GrokColor.black6
                )
            }
            .padding(.leading, 14)
            .padding(.trailing, 12)
            .frame(height: GrokMetrics.inputButton)
            .hoverBackground(
                imageVM.isStylePopoverPresented ? GrokColor.white1 : GrokColor.white2,
                hover: GrokColor.white1,
                cornerRadius: GrokMetrics.inputButton / 2
            )
        }
        .buttonStyle(GrokButtonStyle())
        .popover(isPresented: $imageVM.isStylePopoverPresented, arrowEdge: .top) {
            ImageStylePopover(style: $imageVM.style, ratio: $imageVM.ratio)
        }
    }

    private var generateButton: some View {
        let isGenerating = imageVM.isGenerating
        let isActive = imageVM.canGenerate || isGenerating
        let symbol: String = isGenerating ? "stop.fill" : "sparkles"
        let label: String = isGenerating ? "Stop" : "Generate"
        let fill: Color = isActive ? GrokColor.black1 : GrokColor.white6

        return Button {
            if isGenerating {
                imageVM.stop()
            } else {
                imageVM.generate()
            }
        } label: {
            HStack(spacing: 8) {
                SymbolIcon(symbol, size: 16, color: .white)
                Text(label)
                    .grokText(.bodyMedium, color: .white)
                    .fixedSize()
            }
            .padding(.leading, 16)
            .padding(.trailing, 20)
            .frame(height: GrokMetrics.inputButton)
            .background(Capsule().fill(fill))
        }
        .buttonStyle(GrokButtonStyle())
        .disabled(!isActive)
        .animation(.easeOut(duration: 0.15), value: isActive)
    }
}
