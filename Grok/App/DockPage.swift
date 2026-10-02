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

    @StateObject var screenSwitchVM = ScreenSwitchViewModel()
    @StateObject private var chatVM = ChatViewModel()
    @StateObject private var imageVM = ImageViewModel()
    @StateObject private var pdfVM = PDFViewModel()

    @State var containerWidth: CGFloat = 0
    @State var containerHeight: CGFloat = 0

    var body: some View {
        GeometryReader { geometry in

            ZStack(alignment: .leading) {
                HStack(spacing: 0) {
                    if !isSidebarCollapsed {
                        sidebar(reservesTitleBarSpace: true)
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
            }
            // The window hides its title bar, so the content takes the full
            // height rather than starting below a bar that is not drawn.
            .ignoresSafeArea(.container, edges: .top)
            .animation(.easeOut(duration: 0.2), value: screenSwitchVM.isSidebarPresented)
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
            reservesTitleBarSpace: reservesTitleBarSpace
        )
    }
}
