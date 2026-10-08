//
//  PDFModels.swift
//  Grok
//
//  Created by Tricentric Labs on 01/10/2026.
//

import Foundation

/// A PDF the user has dropped or chosen, with the facts the file row shows.
nonisolated struct PDFDocumentInfo: Identifiable, Equatable {
    let id: UUID
    let url: URL
    let name: String
    let pageCount: Int
    let byteCount: Int
    /// Carried from the unlock sheet, because summarizing reopens the file and
    /// a locked document stays locked on every fresh open.
    var password: String?

    init(
        id: UUID = UUID(),
        url: URL,
        name: String,
        pageCount: Int,
        byteCount: Int,
        password: String? = nil
    ) {
        self.id = id
        self.url = url
        self.name = name
        self.pageCount = pageCount
        self.byteCount = byteCount
        self.password = password
    }

    /// "24 pages · 3.2 MB"
    var subtitle: String {
        "\(pageCount) page\(pageCount == 1 ? "" : "s") · \(formattedSize)"
    }

    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: Int64(byteCount), countStyle: .file)
    }
}

nonisolated enum SummaryLength: String, CaseIterable, Identifiable, Hashable {
    case brief = "Brief"
    case standard = "Standard"
    case detailed = "Detailed"

    var id: String { rawValue }

    /// The raw value is what is stored, so it stays English; the title is what
    /// is shown, and follows the app's language.
    var title: String { ("pdf.length." + rawValue.lowercased()).localized }
}

nonisolated struct SummarySection: Identifiable, Equatable {
    let id: UUID
    let title: String
    let page: Int

    init(id: UUID = UUID(), title: String, page: Int) {
        self.id = id
        self.title = title
        self.page = page
    }

    var pageLabel: String { "pdf.pageLabel".localized(page) }
}

nonisolated struct PDFSummary: Equatable {
    let title: String
    let overview: String
    let keyPoints: [String]
    let sections: [SummarySection]

    /// Plain-text rendering for the Copy action in the summary toolbar.
    var plainText: String {
        var lines = [title, "", overview, "", "Key Points"]
        lines += keyPoints.enumerated().map { "\($0.offset + 1). \($0.element)" }
        lines += ["", "Important Sections"]
        lines += sections.map { "\($0.title) — \($0.pageLabel)" }
        return lines.joined(separator: "\n")
    }
}

/// Everything the PDF flow can be showing, from the empty drop zone through
/// to a finished summary.
nonisolated enum PDFFlowState: Equatable {
    case empty
    case dragging(fileName: String?)
    case selected(PDFDocumentInfo)
    case processing(PDFDocumentInfo)
    case summarized(PDFDocumentInfo, PDFSummary)
    case failed(fileName: String, reason: String)
}
