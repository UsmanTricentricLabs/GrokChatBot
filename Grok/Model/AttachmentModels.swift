//
//  AttachmentModels.swift
//  Grok
//
//  Created by Tricentric Labs on 02/10/2026.
//

import Foundation
import UniformTypeIdentifiers

/// What kind of file the composer is carrying. The three kinds the attach
/// button offers each reach the model as text, so the kind only decides how
/// that text is extracted and how the chip is drawn.
nonisolated enum AttachmentKind: String, Equatable {
    case text
    case pdf
    case image

    var symbolName: String {
        switch self {
        case .text: return "doc.text"
        case .pdf: return "doc.richtext"
        case .image: return "photo"
        }
    }

    /// How the extracted text is introduced to the model.
    var contextLabel: String {
        switch self {
        case .text: return "attachment.kind.text".localized
        case .pdf: return "attachment.kind.pdf".localized
        case .image: return "image"
        }
    }

    /// The types the open panel and the drop target accept.
    static var acceptedContentTypes: [UTType] {
        var types: [UTType] = [.plainText, .utf8PlainText, .text, .pdf, .image, .png, .jpeg]
        if let markdown = UTType("net.daringfireball.markdown") { types.append(markdown) }
        types.append(contentsOf: [.commaSeparatedText, .json])
        return types
    }
}

/// A file the user has attached to a prompt, already read and reduced to the
/// text the model will see.
nonisolated struct ChatAttachment: Identifiable, Equatable {
    let id: UUID
    let name: String
    let kind: AttachmentKind
    let byteCount: Int
    /// What the file says, as plain text: the file's contents, the PDF's
    /// pages, or the text recognized in an image.
    let text: String
    /// Pages, for a PDF.
    let pageCount: Int?
    /// A small PNG preview, for an image chip.
    let previewData: Data?

    init(
        id: UUID = UUID(),
        name: String,
        kind: AttachmentKind,
        byteCount: Int,
        text: String,
        pageCount: Int? = nil,
        previewData: Data? = nil
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.byteCount = byteCount
        self.text = text
        self.pageCount = pageCount
        self.previewData = previewData
    }

    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: Int64(byteCount), countStyle: .file)
    }

    /// "12 pages · 1.2 MB" under the chip title.
    var subtitle: String {
        guard let pageCount else { return formattedSize }
        return "\(pageCount) page\(pageCount == 1 ? "" : "s") · \(formattedSize)"
    }

    /// True when nothing readable came out of the file. The prompt still
    /// sends — the model is simply told the file carried no text.
    var hasText: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

/// The one size rule every file in the app is held to, wherever it arrives —
/// the chat composer or the PDF drop zone.
nonisolated enum FileImportLimits {
    static let byteLimit = 5 * 1024 * 1024

    /// Written out rather than formatted: `ByteCountFormatter` renders this
    /// limit as "5.2 MB", which reads like an odd number to promise.
    static let formattedByteLimit = "5 MB"
}

/// Everything that can go wrong while reading a file the user picked, each
/// phrased as the sentence the screen shows. Shared by the chat composer and
/// the PDF flow so both say the same thing about the same problem.
nonisolated enum AttachmentError: LocalizedError, Equatable {
    case tooLarge(name: String, byteCount: Int)
    case unsupportedType(name: String)
    case corrupted(name: String)
    case passwordProtected(name: String)
    case incorrectPassword
    case empty(name: String)

    var errorDescription: String? {
        switch self {
        case .tooLarge(let name, let byteCount):
            let size = ByteCountFormatter.string(fromByteCount: Int64(byteCount), countStyle: .file)
            return "attachment.tooLarge".localized(name, size, FileImportLimits.formattedByteLimit)
        case .unsupportedType(let name):
            return "“\(name)” can’t be attached. Choose a text file, a PDF or an image."
        case .corrupted(let name):
            return "“\(name)” appears to be corrupted and could not be opened."
        case .passwordProtected(let name):
            return "“\(name)” is password-protected. Enter its password to open it."
        case .incorrectPassword:
            return "attachment.wrongPassword".localized
        case .empty(let name):
            return "“\(name)” has no readable text."
        }
    }

    /// The short line the PDF file row shows under the file's name.
    var rowDetail: String {
        errorDescription ?? "attachment.unreadable".localized
    }

    /// The locked case is answered by the password sheet rather than a banner.
    var lockedFileName: String? {
        if case .passwordProtected(let name) = self { return name }
        return nil
    }
}
