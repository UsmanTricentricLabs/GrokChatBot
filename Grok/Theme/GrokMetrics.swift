//
//  GrokMetrics.swift
//  Grok
//
//  Created by Tricentric Labs on 01/10/2026.
//

import CoreGraphics

/// Shared geometry from the design file. The design is drawn on a 1200×750
/// frame whose sidebar is 200pt wide, so these values are used as points.
enum GrokMetrics {

    // MARK: Chrome

    static let headerHeight: CGFloat = 65
    static let sidebarWidth: CGFloat = 200
    static let sidebarMinWidth: CGFloat = 188
    static let sidebarMaxWidth: CGFloat = 260
    /// Below this window width the sidebar collapses to an overlay drawer.
    static let sidebarCollapseWidth: CGFloat = 900
    /// Clearance above the sidebar's first row. The window hides its title bar
    /// but still draws the traffic lights over the top-left of the rail, so
    /// this is the lights' height plus a little breathing room.
    static let trafficLightInset: CGFloat = 36

    // MARK: Content rhythm

    static let contentPadding: CGFloat = 20
    static let readingWidth: CGFloat = 800
    static let heroWidth: CGFloat = 804
    static let bubbleMaxWidth: CGFloat = 640
    static let mediaWidth: CGFloat = 640
    /// Media is capped in both directions so a tall ratio still leaves room
    /// for the caption and actions above the composer.
    static let mediaMaxHeight: CGFloat = 360

    // MARK: Radii

    static let cardRadius: CGFloat = 28
    static let tileRadius: CGFloat = 20
    static let navItemRadius: CGFloat = 16
    static let chipRadius: CGFloat = 14

    // MARK: Components

    static let cardSize = CGSize(width: 252, height: 160)
    static let inputMinHeight: CGFloat = 72
    static let inputButton: CGFloat = 48
    static let inputMaxLines = 6
}
