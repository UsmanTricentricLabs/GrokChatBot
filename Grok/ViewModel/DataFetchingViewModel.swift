//
//  DataFetchingViewModel.swift
//  Grok
//
//  Created by Tricentric Labs on 01/10/2026.
//

import Foundation
import SwiftUI
internal import Combine

/// Owns which of the three flows — Chat, AI Image, PDF Summary — is on screen.
class ScreenSwitchViewModel: ObservableObject {

    @Published var screen: Screen = .home
    /// Drives the sidebar drawer once the window is too narrow to hold it.
    @Published var isSidebarPresented: Bool = false

    enum Screen: Int, CaseIterable {
        case home = 1
        case createImage = 2
        case pdfSummary = 3
    }

    func show(_ screen: Screen) {
        self.screen = screen
        isSidebarPresented = false
    }
}
