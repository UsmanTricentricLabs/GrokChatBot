//
//  ImageHistoryStore.swift
//  Grok
//
//  Created by Tricentric Labs on 05/10/2026.
//

import AppKit
import CoreData

/// Where the image gallery lives between launches.
///
/// Each finished picture is one row, with the artwork stored as PNG beside the
/// prompt that made it — so the sidebar thumbnails and the gallery come back
/// exactly as they were left.
@MainActor
struct ImageHistoryStore {

    static let shared = ImageHistoryStore()

    private let context: NSManagedObjectContext

    init(controller: PersistenceController = .shared) {
        self.context = controller.container.viewContext
    }

    // MARK: Reading

    /// Every stored image, newest first — the order the gallery and the
    /// sidebar both expect.
    func load() -> [GeneratedImage] {
        let request = NSFetchRequest<CDGeneratedImage>(entityName: "CDGeneratedImage")
        request.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: false)]
        do {
            return try context.fetch(request).compactMap(Self.image(from:))
        } catch {
            NSLog("Image history could not be read: \(error.localizedDescription)")
            return []
        }
    }

    // MARK: Writing

    /// Replaces the stored gallery with what the view model is holding. The
    /// list is small enough that rewriting it whole keeps deletes, retries and
    /// new pictures on one path.
    func save(_ images: [GeneratedImage]) {
        do {
            let request = NSFetchRequest<CDGeneratedImage>(entityName: "CDGeneratedImage")
            for existing in try context.fetch(request) {
                context.delete(existing)
            }

            for image in images where image.state == .ready {
                // A picture with no artwork would come back as an empty tile,
                // so only what can actually be drawn again is written.
                guard let artwork = image.image, let data = ArtworkExporter.pngData(artwork) else { continue }

                let row = CDGeneratedImage(context: context)
                row.id = image.id
                row.prompt = image.prompt
                row.styleRaw = image.style.rawValue
                row.ratioRaw = image.ratio.rawValue
                row.createdAt = image.createdAt
                row.artworkData = data
            }

            guard context.hasChanges else { return }
            try context.save()
        } catch {
            NSLog("Image history could not be saved: \(error.localizedDescription)")
            context.rollback()
        }
    }

    // MARK: Mapping

    private static func image(from row: CDGeneratedImage) -> GeneratedImage? {
        guard let data = row.artworkData, let artwork = NSImage(data: data) else { return nil }

        return GeneratedImage(
            id: row.id ?? UUID(),
            prompt: row.prompt ?? "",
            style: ImageStyle(rawValue: row.styleRaw ?? "") ?? .photographic,
            ratio: ImageAspectRatio(rawValue: row.ratioRaw ?? "") ?? .square,
            state: .ready,
            createdAt: row.createdAt ?? Date(),
            image: artwork
        )
    }
}
