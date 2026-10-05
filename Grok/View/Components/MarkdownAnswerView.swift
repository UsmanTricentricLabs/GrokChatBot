//
//  MarkdownAnswerView.swift
//  Grok
//
//  Created by Tricentric Labs on 05/10/2026.
//

import SwiftUI
import AIFormattingKit
internal import Combine

/// The formatter's style, tuned to the app's type ramp.
///
/// AIFormattingKit reads its measurements from the environment, so the whole
/// answer — paragraphs, lists, tables, code — lands on the same 16/28 body
/// rhythm the rest of the thread uses.
nonisolated struct GrokMarkdownStyle: MarkdownTextStyle {
    func apply(to configuration: inout MarkdownTextStyleConfiguration) {
        configuration.baseFontSize = GrokTextStyle.bodyRelaxed.size
        configuration.inlineLineSpacing = GrokTextStyle.bodyRelaxed.lineSpacing
        configuration.paragraphSpacing = 10
        configuration.blockSpacing = 14
        configuration.listMarkerWidth = 20
        configuration.codeContentPadding = 12
    }
}

/// An assistant answer rendered from its original Markdown, with the blinking
/// caret kept while the reply is still arriving.
struct MarkdownAnswerView: View {
    let text: String
    var showsCaret: Bool

    @State private var isCaretVisible = true
    private let blink = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()

    var body: some View {
        Markdown(text + caret)
            .markdownTextStyle { GrokMarkdownStyle() }
            .frame(maxWidth: .infinity, alignment: .leading)
            .onReceive(blink) { _ in
                guard showsCaret else { return }
                isCaretVisible.toggle()
            }
    }

    /// A figure space stands in for the hidden caret so the last line does not
    /// change length between blinks.
    private var caret: String {
        guard showsCaret else { return "" }
        return isCaretVisible ? "\u{258F}" : "\u{2007}"
    }
}
