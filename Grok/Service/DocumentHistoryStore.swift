//
//  DocumentHistoryStore.swift
//  Grok
//
//  Created by Tricentric Labs on 05/10/2026.
//

import CoreData
import Foundation

/// One summarized PDF as the sidebar remembers it: the file it was made from,
/// the summary itself, and the questions asked about it.
nonisolated struct SummarizedDocument: Identifiable, Equatable {
    var id: UUID { info.id }
    let info: PDFDocumentInfo
    let summary: PDFSummary
    let followUps: [ChatMessage]
}

/// Where the "Documents" list lives between launches.
///
/// The summary and its follow-ups are kept with the record, so reopening a
/// document from the sidebar shows what was read before without touching the
/// file again — which matters because a sandboxed app cannot reach a picked
/// file after a relaunch.
@MainActor
struct DocumentHistoryStore {

    static let shared = DocumentHistoryStore()

    private let context: NSManagedObjectContext

    init(controller: PersistenceController = .shared) {
        self.context = controller.container.viewContext
    }

    // MARK: Reading

    /// The stored documents in sidebar order, newest first.
    func load() -> [SummarizedDocument] {
        let request = NSFetchRequest<CDSummarizedDocument>(entityName: "CDSummarizedDocument")
        request.sortDescriptors = [NSSortDescriptor(key: "order", ascending: true)]
        do {
            return try context.fetch(request).compactMap(Self.document(from:))
        } catch {
            NSLog("Document history could not be read: \(error.localizedDescription)")
            return []
        }
    }

    // MARK: Writing

    func save(_ documents: [SummarizedDocument]) {
        do {
            let request = NSFetchRequest<CDSummarizedDocument>(entityName: "CDSummarizedDocument")
            for existing in try context.fetch(request) {
                context.delete(existing)
            }

            for (index, document) in documents.enumerated() {
                let row = CDSummarizedDocument(context: context)
                row.id = document.info.id
                row.urlString = document.info.url.absoluteString
                row.name = document.info.name
                row.pageCount = Int32(document.info.pageCount)
                row.byteCount = Int64(document.info.byteCount)
                row.order = Int32(index)
                row.summaryData = try? Self.encoder.encode(SummaryDTO(document.summary))
                row.followUpsData = document.followUps.isEmpty
                    ? nil
                    : try? Self.encoder.encode(document.followUps.map(MessageDTO.init))
            }

            guard context.hasChanges else { return }
            try context.save()
        } catch {
            NSLog("Document history could not be saved: \(error.localizedDescription)")
            context.rollback()
        }
    }

    // MARK: Mapping

    private static func document(from row: CDSummarizedDocument) -> SummarizedDocument? {
        guard let urlString = row.urlString,
              let url = URL(string: urlString),
              let summary = row.summaryData.flatMap({ try? decoder.decode(SummaryDTO.self, from: $0) })?.summary
        else { return nil }

        let followUps = (row.followUpsData.flatMap { try? decoder.decode([MessageDTO].self, from: $0) } ?? [])
            .map(\.message)

        return SummarizedDocument(
            info: PDFDocumentInfo(
                id: row.id ?? UUID(),
                url: url,
                name: row.name ?? url.lastPathComponent,
                pageCount: Int(row.pageCount),
                byteCount: Int(row.byteCount)
            ),
            summary: summary,
            followUps: followUps
        )
    }

    private static let encoder = JSONEncoder()
    private static let decoder = JSONDecoder()
}

// MARK: - Stored shapes

private struct SummaryDTO: Codable {
    let title: String
    let overview: String
    let keyPoints: [String]
    let sections: [SectionDTO]

    init(_ summary: PDFSummary) {
        title = summary.title
        overview = summary.overview
        keyPoints = summary.keyPoints
        sections = summary.sections.map(SectionDTO.init)
    }

    var summary: PDFSummary {
        PDFSummary(
            title: title,
            overview: overview,
            keyPoints: keyPoints,
            sections: sections.map(\.section)
        )
    }
}

private struct SectionDTO: Codable {
    let id: UUID
    let title: String
    let page: Int

    init(_ section: SummarySection) {
        id = section.id
        title = section.title
        page = section.page
    }

    var section: SummarySection {
        SummarySection(id: id, title: title, page: page)
    }
}
