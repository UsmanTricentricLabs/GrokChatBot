//
//  ImageCanvasResetTests.swift
//  GrokTests
//
//  Created by Tricentric Labs on 02/10/2026.
//

import XCTest
@testable import Grok

/// "Create Image" in the sidebar opens a fresh canvas the way New Chat opens a
/// fresh conversation, instead of returning to the last result.
@MainActor
final class ImageCanvasResetTests: XCTestCase {

    private var viewModel: ImageViewModel!
    /// A store of its own, so a test never reads or overwrites the gallery the
    /// app has saved on this machine.
    private var controller: PersistenceController!

    override func setUp() async throws {
        try await super.setUp()
        StubURLProtocol.reset()
        controller = PersistenceController(inMemory: true)
        viewModel = ImageViewModel(
            service: GatewayImageGenerationService(client: GatewayClient(session: StubURLProtocol.session())),
            history: ImageHistoryStore(controller: controller)
        )
    }

    override func tearDown() async throws {
        StubURLProtocol.reset()
        viewModel = nil
        controller = nil
        try await super.tearDown()
    }

    func testStartingANewImageClearsTheResultAndThePrompt() async throws {
        try await generateOne(prompt: "A lighthouse at dusk")
        XCTAssertNotNil(viewModel.latestImage)

        viewModel.prompt = "half-typed idea"
        viewModel.startNewImage()

        XCTAssertNil(viewModel.latestImage, "The screen should be back to its empty state")
        XCTAssertEqual(viewModel.prompt, "")
        XCTAssertNil(viewModel.selectedImageID)
    }

    func testTheHistorySurvivesAReset() async throws {
        try await generateOne(prompt: "A lighthouse at dusk")

        viewModel.startNewImage()

        XCTAssertTrue(viewModel.hasHistory, "The sidebar and gallery keep what was made")
        XCTAssertEqual(viewModel.images.count, 1)
    }

    func testTheGalleryAndStylePopoverAreDismissed() async throws {
        try await generateOne(prompt: "A lighthouse at dusk")
        viewModel.isGalleryPresented = true
        viewModel.isStylePopoverPresented = true

        viewModel.startNewImage()

        XCTAssertFalse(viewModel.isGalleryPresented)
        XCTAssertFalse(viewModel.isStylePopoverPresented)
    }

    func testGeneratingAgainAddsToTheSameThread() async throws {
        try await generateOne(prompt: "A lighthouse at dusk")
        try await generateOne(prompt: "The same lighthouse in fog")

        XCTAssertEqual(
            viewModel.threadImages.map(\.prompt),
            ["A lighthouse at dusk", "The same lighthouse in fog"],
            "Generating again should continue the session, not start a new screen"
        )
    }

    func testOnlyCreateImageStartsAFreshThread() async throws {
        try await generateOne(prompt: "A lighthouse at dusk")
        try await generateOne(prompt: "The same lighthouse in fog")

        viewModel.startNewImage()

        XCTAssertTrue(viewModel.threadImages.isEmpty)
        XCTAssertEqual(viewModel.images.count, 2, "Both stay in the history")
    }

    func testAThumbnailFromAnEarlierSessionOpensOnItsOwn() async throws {
        try await generateOne(prompt: "A lighthouse at dusk")
        let earlier = try XCTUnwrap(viewModel.images.first)
        viewModel.startNewImage()
        try await generateOne(prompt: "A harbour at dawn")

        viewModel.select(earlier)

        XCTAssertEqual(viewModel.threadImages.map(\.id), [earlier.id])
    }

    func testStoppingAGenerationLeavesTheEarlierTurnsInPlace() async throws {
        try await generateOne(prompt: "A lighthouse at dusk")

        StubURLProtocol.stub = .json(TestFixtures.imageResponse)
        viewModel.prompt = "A harbour at dawn"
        viewModel.generate()
        viewModel.stop()

        XCTAssertEqual(viewModel.threadImages.map(\.prompt), ["A lighthouse at dusk"])
    }

    func testGeneratingAgainLeavesTheFreshCanvas() async throws {
        try await generateOne(prompt: "A lighthouse at dusk")
        viewModel.startNewImage()

        try await generateOne(prompt: "A harbour at dawn")

        XCTAssertEqual(viewModel.latestImage?.prompt, "A harbour at dawn")
        XCTAssertEqual(viewModel.images.count, 2)
    }

    func testPickingAThumbnailAfterAResetShowsThatImage() async throws {
        try await generateOne(prompt: "A lighthouse at dusk")
        let made = try XCTUnwrap(viewModel.images.first)
        viewModel.startNewImage()

        viewModel.select(made)

        XCTAssertEqual(viewModel.latestImage?.id, made.id)
    }

    // MARK: Helpers

    private func generateOne(prompt: String) async throws {
        StubURLProtocol.stub = .json(TestFixtures.imageResponse)
        viewModel.prompt = prompt
        viewModel.generate()
        try await waitUntil { self.viewModel.latestImage?.state == .ready }
    }

    private func waitUntil(
        _ condition: @escaping () -> Bool,
        timeout: TimeInterval = 2
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            if Date() > deadline { XCTFail("Timed out waiting for the generation to finish"); return }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
    }
}

/// Saved images are named by the moment they were made, so a second save does
/// not land on a file that is already there.
@MainActor
final class ImageFileNameTests: XCTestCase {

    func testTheNameCarriesTheMomentTheImageWasMade() {
        let made = DateComponents(
            calendar: Calendar(identifier: .gregorian),
            timeZone: TimeZone.current,
            year: 2026, month: 10, day: 2, hour: 14, minute: 52, second: 31
        ).date!

        XCTAssertEqual(
            ImageViewModel.fileName(for: image(createdAt: made)),
            "Grok Image 2026-10-02 at 14.52.31.png"
        )
    }

    func testTwoImagesDoNotProposeTheSameName() {
        let first = image(createdAt: Date(timeIntervalSince1970: 1_000_000))
        let second = image(createdAt: Date(timeIntervalSince1970: 1_000_060))

        XCTAssertNotEqual(ImageViewModel.fileName(for: first), ImageViewModel.fileName(for: second))
    }

    func testSavingTheSameImageTwiceProposesTheSameName() {
        let made = image(createdAt: Date(timeIntervalSince1970: 1_000_000))

        XCTAssertEqual(ImageViewModel.fileName(for: made), ImageViewModel.fileName(for: made))
    }

    func testTheNameIsLegalOnDisk() {
        let name = ImageViewModel.fileName(for: image(createdAt: Date()))

        XCTAssertFalse(name.contains(":"), "A colon is not a legal path character")
        XCTAssertFalse(name.contains("/"))
        XCTAssertTrue(name.hasSuffix(".png"))
    }

    private func image(createdAt: Date) -> GeneratedImage {
        GeneratedImage(
            prompt: "A lighthouse at dusk",
            style: .photographic,
            ratio: .square,
            state: .ready,
            createdAt: createdAt
        )
    }
}
