//
//  ArtworkExporterTests.swift
//  GrokTests
//
//  Created by Tricentric Labs on 01/10/2026.
//

import AppKit
import XCTest
@testable import Grok

/// Covers saving a generated image, the action behind the download button.
final class ArtworkExporterTests: XCTestCase {

    private var destination: URL!

    override func setUp() {
        super.setUp()
        destination = FileManager.default.temporaryDirectory
            .appendingPathComponent("GrokExport-\(UUID().uuidString).png")
    }

    override func tearDown() {
        if let destination { try? FileManager.default.removeItem(at: destination) }
        destination = nil
        super.tearDown()
    }

    func testWritesAPNGAtTheImagesOwnSize() throws {
        try ArtworkExporter.writePNG(Self.makeImage(width: 64, height: 32), to: destination)

        let written = try XCTUnwrap(NSImage(contentsOf: destination))
        let rep = try XCTUnwrap(written.representations.first)
        XCTAssertEqual(rep.pixelsWide, 64)
        XCTAssertEqual(rep.pixelsHigh, 32)
    }

    func testWrittenFileIsRecognisablePNGData() throws {
        try ArtworkExporter.writePNG(Self.makeImage(width: 8, height: 8), to: destination)

        let data = try Data(contentsOf: destination)
        XCTAssertEqual(Array(data.prefix(4)), [0x89, 0x50, 0x4E, 0x47], "Expected a PNG signature.")
    }

    /// The save panel hands back a URL the app must be able to write to; an
    /// unwritable one has to surface as an error, not vanish.
    func testUnwritableDestinationThrows() {
        let unwritable = URL(fileURLWithPath: "/System/grok-should-not-write.png")

        XCTAssertThrowsError(try ArtworkExporter.writePNG(Self.makeImage(width: 8, height: 8), to: unwritable))
    }

    func testImageWithNoBitmapRepresentationThrows() {
        XCTAssertThrowsError(try ArtworkExporter.writePNG(NSImage(), to: destination)) { error in
            XCTAssertEqual(error as? ArtworkExportError, .encodingFailed)
        }
    }

    private static func makeImage(width: Int, height: Int) -> NSImage {
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: width, pixelsHigh: height,
            bitsPerSample: 8, samplesPerPixel: 4,
            hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0, bitsPerPixel: 0
        )!

        let image = NSImage(size: NSSize(width: width, height: height))
        image.addRepresentation(rep)
        return image
    }
}
