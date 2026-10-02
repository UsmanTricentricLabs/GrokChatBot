//
//  GrokAsset.swift
//  Grok
//
//  Created by Tricentric Labs on 01/10/2026.
//

import Foundation

/// Names of the vector assets shipped in `Assets.xcassets`, kept in one place
/// so a renamed asset is a single compile-time edit.
enum GrokAsset {

    // MARK: Brand

    /// The Grok mark, used for the hero and beside streaming answers.
    static let mark = "mainHomeIcon"

    // MARK: Sidebar

    static let sidebarBackground = "sideBarBackground"
    static let newChat = "sideBarNewChat"
    static let createImage = "sideBarCreateImage"
    static let pdfSummary = "sideBarPDF"
    /// Planet illustration used by every empty state.
    static let emptyState = "noChat"

    // MARK: Header

    static let language = "languageIcon"
    static let settings = "settingsIcon"

    // MARK: Prompt starters

    static let codeAndDebug = "codeAndDebug"
    static let writeAndSummarize = "writeAndSummarize"
    static let dataInsights = "dataInsights"

    // MARK: Input bar
    //
    // These four ship with their circular plate baked in, so they are drawn at
    // full button size rather than inset inside a background.

    static let attach = "addIcon"
    static let microphone = "micIcon"
    static let send = "sendIcon"
    static let sendDisabled = "unSendIcon"

    // MARK: Message actions

    static let copy = "copyIcon"
    static let speaker = "speakerIcon"
    static let regenerate = "regenerateIcon"
}
