//
//  HistoryPersistenceTests.swift
//  GrokTests
//
//  Created by Tricentric Labs on 05/10/2026.
//

import AppKit
import XCTest
@testable import Grok

/// Covers what survives a relaunch: the image gallery and the summarized
/// documents in the sidebar, each with the work that produced it.
@MainActor
final class HistoryPersistenceTests: XCTestCase {

    private var controller: PersistenceController!
    /// Held for the length of the test: the view models are `@MainActor`
    /// objects and are torn down with the case, not mid-assertion.
    private var pdfVM: PDFViewModel!

    override func setUp() async throws {
        try await super.setUp()
        controller = PersistenceController(inMemory: true)
    }

    override func tearDown() async throws {
        pdfVM = nil
        controller = nil
        try await super.tearDown()
    }

    // MARK: Images

    func testAFinishedImageComesBackWithItsArtwork() throws {
        let store = ImageHistoryStore(controller: controller)
        let artwork = try XCTUnwrap(Self.artwork())
        let image = GeneratedImage(
            prompt: "A lighthouse at dusk",
            style: .cinematic,
            ratio: .wide,
            state: .ready,
            image: artwork
        )

        store.save([image])
        let restored = try XCTUnwrap(ImageHistoryStore(controller: controller).load().first)

        XCTAssertEqual(restored.id, image.id)
        XCTAssertEqual(restored.prompt, "A lighthouse at dusk")
        XCTAssertEqual(restored.style, .cinematic)
        XCTAssertEqual(restored.ratio, .wide)
        XCTAssertEqual(restored.state, .ready)
        XCTAssertNotNil(restored.image, "The picture itself is what the gallery draws.")
    }

    func testAnUnfinishedImageIsNotKept() throws {
        let store = ImageHistoryStore(controller: controller)
        store.save([GeneratedImage(prompt: "Still drawing", style: .anime, ratio: .square)])

        XCTAssertTrue(store.load().isEmpty, "A spinner is not worth restoring.")
    }

    // MARK: Documents

    func testASummarizedDocumentComesBackWithItsSummaryAndQuestions() throws {
        let store = DocumentHistoryStore(controller: controller)
        let record = Self.record()

        store.save([record])
        let restored = try XCTUnwrap(DocumentHistoryStore(controller: controller).load().first)

        XCTAssertEqual(restored.info, record.info)
        XCTAssertEqual(restored.summary, record.summary)
        XCTAssertEqual(restored.followUps.count, 2)
        XCTAssertEqual(restored.followUps[1].blocks, [.markdown("**Yes.** It covers 2026.")])
    }

    func testTheSidebarListIsRestoredAndItsSummaryReopens() throws {
        let store = DocumentHistoryStore(controller: controller)
        let record = Self.record()
        store.save([record])

        pdfVM = PDFViewModel(history: DocumentHistoryStore(controller: controller))
        let viewModel = pdfVM!
        XCTAssertEqual(viewModel.summarizedDocuments.map(\.name), [record.info.name])
        XCTAssertNil(viewModel.summary, "The flow still opens on the drop zone.")

        let listed = try XCTUnwrap(viewModel.summarizedDocuments.first)
        viewModel.select(listed)

        XCTAssertEqual(viewModel.summary, record.summary)
        XCTAssertEqual(viewModel.followUps.count, 2, "Its questions come back with it.")
    }

    // MARK: Fixtures

    private static func artwork() -> NSImage? {
        Data(base64Encoded: TestFixtures.pngBase64).flatMap(NSImage.init(data:))
    }

    private static func record() -> SummarizedDocument {
        SummarizedDocument(
            info: PDFDocumentInfo(
                url: URL(fileURLWithPath: "/tmp/pakistan_wildlife_essay.pdf"),
                name: "pakistan_wildlife_essay.pdf",
                pageCount: 12,
                byteCount: 240_000
            ),
            summary: PDFSummary(
                title: "Wildlife of Pakistan",
                overview: "An overview.",
                keyPoints: ["Snow leopards are recovering."],
                sections: [SummarySection(title: "Habitats", page: 3)]
            ),
            followUps: [
                ChatMessage(role: .user, text: "Is it current?"),
                ChatMessage(role: .assistant, blocks: [.markdown("**Yes.** It covers 2026.")])
            ]
        )
    }
}
