//
//  DockPage.swift
//  Grok
//
//  Created by Tricentric Labs on 01/10/2026.
//

import SwiftUI

/// The app shell: the sidebar rail beside the active flow. Below a narrow
/// breakpoint the rail becomes an overlay drawer so the content keeps a
/// usable measure.
struct DockPage: View {

    // Owned by the app, not by this view: a language change rebuilds the shell,
    // and the conversation, the images and the open document all have to
    // survive that.
    @ObservedObject var screenSwitchVM: ScreenSwitchViewModel
    @ObservedObject var chatVM: ChatViewModel
    @ObservedObject var imageVM: ImageViewModel
    @ObservedObject var pdfVM: PDFViewModel
    @ObservedObject var paywall: PaywallPresenter

    /// The one source of truth for everything to do with the subscription.
    @ObservedObject private var iap = IAPManager.shared

    @Environment(\.layoutDirection) private var layoutDirection

    @State var containerWidth: CGFloat = 0
    @State var containerHeight: CGFloat = 0

    var body: some View {
        GeometryReader { geometry in

            ZStack(alignment: .leading) {
                HStack(spacing: 0) {
                    if !isSidebarCollapsed {
                        // Right to left the rail sits on the far side of the
                        // window, clear of the traffic lights, so it no longer
                        // has to hold space for them — the header does.
                        sidebar(reservesTitleBarSpace: layoutDirection == .leftToRight)
                            .frame(width: sidebarWidth)
                    }

                    // MARK: Main Content

                    ZStack {
                        switch screenSwitchVM.screen {
                        case .home:
                            HomeScreen(
                                screenSwitchVM: screenSwitchVM,
                                chatVM: chatVM,
                                containerWidth: contentWidth,
                                containerHeight: containerHeight,
                                showsSidebarToggle: isSidebarCollapsed
                            )
                        case .createImage:
                            ImageScreen(
                                screenSwitchVM: screenSwitchVM,
                                imageVM: imageVM,
                                containerWidth: contentWidth,
                                containerHeight: containerHeight,
                                showsSidebarToggle: isSidebarCollapsed
                            )
                        case .pdfSummary:
                            PDFScreen(
                                screenSwitchVM: screenSwitchVM,
                                pdfVM: pdfVM,
                                containerWidth: contentWidth,
                                containerHeight: containerHeight,
                                showsSidebarToggle: isSidebarCollapsed
                            )
                        }
                    }
                }

                if isSidebarCollapsed, screenSwitchVM.isSidebarPresented {
                    Color.black.opacity(0.35)
                        .ignoresSafeArea()
                        .onTapGesture { screenSwitchVM.isSidebarPresented = false }

                    sidebar(reservesTitleBarSpace: false)
                        .frame(width: GrokMetrics.sidebarMaxWidth)
                        .shadow(color: .black.opacity(0.25), radius: 24, x: 8, y: 0)
                        .transition(.move(edge: .leading))
                }

                if paywall.isPresented {
                    PaywallOverlay(
                        iap: iap,
                        containerSize: CGSize(width: containerWidth, height: containerHeight)
                    ) {
                        paywall.isPresented = false
                    }
                }
            }
            // The window hides its title bar, so the content takes the full
            // height rather than starting below a bar that is not drawn.
            .ignoresSafeArea(.container, edges: .top)
            .animation(.easeOut(duration: 0.2), value: screenSwitchVM.isSidebarPresented)
            .animation(.easeOut(duration: 0.28), value: paywall.isPresented)
            // The app settles before it asks for money, and asks only once the
            // App Store has confirmed the customer is not already subscribed —
            // so a subscriber never sees the dialog, not even for a frame.
            .task {
                await paywall.offerAtLaunch(using: iap)
            }
            // Covers every way premium can arrive: a purchase, a restore, or a
            // transaction the listener picks up on its own.
            .onChange(of: iap.isPremiumUnlocked) { isPremium in
                if isPremium { paywall.isPresented = false }
            }
            .onAppear {
                containerWidth = geometry.size.width
                containerHeight = geometry.size.height
            }
            .onChange(of: geometry.size) { newValue in
                containerWidth = newValue.width
                containerHeight = newValue.height
            }
        }
    }

    // MARK: Layout

    private var isSidebarCollapsed: Bool {
        containerWidth > 0 && containerWidth < GrokMetrics.sidebarCollapseWidth
    }

    /// Proportional like the design, but clamped so the rail stays legible on
    /// very wide displays and never crowds the content on small ones.
    private var sidebarWidth: CGFloat {
        min(max(containerWidth * 0.17, GrokMetrics.sidebarMinWidth), GrokMetrics.sidebarMaxWidth)
    }

    private var contentWidth: CGFloat {
        isSidebarCollapsed ? containerWidth : containerWidth - sidebarWidth
    }

    private func sidebar(reservesTitleBarSpace: Bool) -> some View {
        SideBarView(
            screenSwitchVM: screenSwitchVM,
            chatVM: chatVM,
            imageVM: imageVM,
            pdfVM: pdfVM,
            containerWidth: sidebarWidth,
            containerHeight: containerHeight,
            reservesTitleBarSpace: reservesTitleBarSpace,
            onUpgrade: { paywall.isPresented = true }
        )
    }
}
