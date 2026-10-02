//
//  ResponseTextParser.swift
//  Grok
//
//  Created by Tricentric Labs on 01/10/2026.
//

import Foundation

/// Turns an assistant reply into the blocks the thread already renders.
///
/// The chat view draws paragraphs and numbered lists, with a medium-weight
/// lead on each list row, so model output is parsed into that same shape
/// rather than rendered as one undifferentiated string.
nonisolated enum ResponseTextParser {

    static func blocks(from text: String) -> [ResponseBlock] {
        var blocks: [ResponseBlock] = []
        var paragraph: [String] = []
        var listItems: [NumberedItem] = []

        func flushParagraph() {
            guard !paragraph.isEmpty else { return }
            blocks.append(.paragraph(paragraph.joined(separator: " ")))
            paragraph.removeAll()
        }

        func flushList() {
            guard !listItems.isEmpty else { return }
            blocks.append(.numberedList(listItems))
            listItems.removeAll()
        }

        for rawLine in text.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)

            if line.isEmpty {
                flushParagraph()
                flushList()
                continue
            }

            if let item = numberedItem(from: line) {
                flushParagraph()
                listItems.append(item)
            } else {
                flushList()
                paragraph.append(stripInlineMarkers(line))
            }
        }

        flushParagraph()
        flushList()
        return blocks.isEmpty ? [.paragraph(text)] : blocks
    }

    /// Matches "1. Lead. Body", pulling out the lead phrase the design sets in
    /// medium weight. Bold markers around the lead are honoured when present.
    private static func numberedItem(from line: String) -> NumberedItem? {
        guard let dot = line.firstIndex(of: "."),
              let number = Int(line[line.startIndex..<dot]),
              number > 0
        else { return nil }

        let remainder = line[line.index(after: dot)...].trimmingCharacters(in: .whitespaces)
        guard !remainder.isEmpty else { return nil }

        if let bold = boldPrefix(of: remainder) {
            return NumberedItem(lead: bold.lead, body: stripInlineMarkers(bold.rest))
        }

        let plain = stripInlineMarkers(remainder)
        guard let breakPoint = plain.firstIndex(where: { $0 == "." || $0 == ":" }) else {
            return NumberedItem(lead: "", body: plain)
        }

        let lead = String(plain[...breakPoint])
        // A lead should be a short opening phrase, not the whole sentence.
        guard lead.split(separator: " ").count <= 4 else {
            return NumberedItem(lead: "", body: plain)
        }

        let body = plain[plain.index(after: breakPoint)...].trimmingCharacters(in: .whitespaces)
        return NumberedItem(lead: lead, body: body)
    }

    private static func boldPrefix(of text: String) -> (lead: String, rest: String)? {
        guard text.hasPrefix("**"),
              let close = text.range(of: "**", range: text.index(text.startIndex, offsetBy: 2)..<text.endIndex)
        else { return nil }

        let lead = String(text[text.index(text.startIndex, offsetBy: 2)..<close.lowerBound])
        let rest = String(text[close.upperBound...]).trimmingCharacters(in: .whitespaces)
        return (lead, rest)
    }

    /// Removes the emphasis and heading markers the thread does not style.
    private static func stripInlineMarkers(_ line: String) -> String {
        var cleaned = line
        while cleaned.hasPrefix("#") || cleaned.hasPrefix(">") {
            cleaned.removeFirst()
            cleaned = cleaned.trimmingCharacters(in: .whitespaces)
        }
        if cleaned.hasPrefix("- ") || cleaned.hasPrefix("* ") {
            cleaned.removeFirst(2)
        }
        return cleaned.replacingOccurrences(of: "**", with: "")
    }
}
