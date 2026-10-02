//
//  PDFImportRulesTests.swift
//  GrokTests
//
//  Created by Tricentric Labs on 02/10/2026.
//

import AppKit
import PDFKit
import XCTest
@testable import Grok

/// The PDF flow is held to the same rules as a chat attachment: five
/// megabytes, a named failure for a damaged file, and an unlock sheet rather
/// than an error for a password-protected one.
@MainActor
final class PDFImportRulesTests: XCTestCase {

    private var scratch: URL!
    private var viewModel: PDFViewModel!

    override func setUp() async throws {
        try await super.setUp()
        scratch = FileManager.default.temporaryDirectory
            .appendingPathComponent("GrokPDFRules-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        viewModel = PDFViewModel()
    }

    override func tearDown() async throws {
        if let scratch { try? FileManager.default.removeItem(at: scratch) }
        scratch = nil
        viewModel = nil
        try await super.tearDown()
    }

    // MARK: Size

    func testTheLimitIsTheSameFiveMegabytesTheComposerApplies() {
        XCTAssertEqual(FileImportLimits.byteLimit, 5 * 1024 * 1024)
        XCTAssertEqual(AttachmentLoader.byteLimit, FileImportLimits.byteLimit)
    }

    func testAPDFOverTheLimitFailsWithItsSize() throws {
        let url = try writePDF(named: "huge.pdf", padTo: FileImportLimits.byteLimit + 1)

        viewModel.open(url)

        XCTAssertNil(viewModel.passwordRequest)
        let reason = try failureReason()
        XCTAssertTrue(reason.contains("5 MB"), reason)
    }

    func testAPDFUnderTheLimitOpens() throws {
        let url = try writePDF(named: "report.pdf")

        viewModel.open(url)

        XCTAssertEqual(viewModel.document?.name, "report.pdf")
        XCTAssertNil(viewModel.passwordRequest)
    }

    // MARK: Corruption

    func testATruncatedPDFIsNamedAsCorrupted() throws {
        let url = scratch.appendingPathComponent("broken.pdf")
        try Data("%PDF-1.4 and then nothing".utf8).write(to: url)

        viewModel.open(url)

        let reason = try failureReason()
        XCTAssertTrue(reason.contains("corrupted"), reason)
    }

    func testANonPDFDropIsRefusedByName() throws {
        let url = scratch.appendingPathComponent("notes.txt")
        try Data("plain text".utf8).write(to: url)

        viewModel.open(url)

        let reason = try failureReason()
        XCTAssertFalse(reason.isEmpty)
    }

    // MARK: Passwords

    func testALockedPDFRaisesTheUnlockSheetRatherThanAnError() throws {
        let url = try writeLockedPDF(password: "open-sesame")

        viewModel.open(url)

        XCTAssertEqual(viewModel.passwordRequest?.name, url.lastPathComponent)
        XCTAssertEqual(viewModel.state, .empty)
    }

    func testTheWrongPasswordKeepsTheSheetOpenAndSaysSo() throws {
        let url = try writeLockedPDF(password: "open-sesame")
        viewModel.open(url)

        viewModel.submitPassword("guess")

        let request = try XCTUnwrap(viewModel.passwordRequest)
        XCTAssertEqual(request.name, url.lastPathComponent)
        XCTAssertEqual(request.errorMessage, AttachmentError.incorrectPassword.errorDescription)
        XCTAssertFalse(request.isUnlocking)
    }

    func testTheRightPasswordSelectsTheDocumentAndIsKeptForSummarizing() throws {
        let url = try writeLockedPDF(password: "open-sesame")
        viewModel.open(url)

        viewModel.submitPassword("open-sesame")

        XCTAssertNil(viewModel.passwordRequest)
        let document = try XCTUnwrap(viewModel.document)
        XCTAssertEqual(document.pageCount, 1)
        // Reopening to summarize re-locks the file, so the password travels on.
        XCTAssertEqual(document.password, "open-sesame")
    }

    func testAnUnlockedDocumentCanActuallyBeRead() async throws {
        let url = try writeLockedPDF(password: "open-sesame")
        viewModel.open(url)
        viewModel.submitPassword("open-sesame")
        let document = try XCTUnwrap(viewModel.document)

        StubURLProtocol.reset()
        defer { StubURLProtocol.reset() }
        StubURLProtocol.stub = .json("{\"error\":{\"code\":\"server_error\"}}", status: 503)
        let service = PDFSummaryService(client: GatewayClient(session: StubURLProtocol.session()))

        // The Gateway is refused, so this exercises the local path — which can
        // only produce a summary if the pages were genuinely readable.
        let summary = try await service.summarize(document, length: .brief) { _ in }

        XCTAssertFalse(summary.overview.isEmpty)
    }

    func testCancellingTheSheetLeavesTheDropZoneReady() throws {
        let url = try writeLockedPDF(password: "open-sesame")
        viewModel.open(url)

        viewModel.cancelPasswordRequest()

        XCTAssertNil(viewModel.passwordRequest)
        XCTAssertEqual(viewModel.state, .empty)
    }

    // MARK: Helpers

    private func failureReason(
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> String {
        guard case .failed(_, let reason) = viewModel.state else {
            XCTFail("Expected a failure, got \(viewModel.state)", file: file, line: line)
            throw XCTSkip("no failure to inspect")
        }
        return reason
    }

    private func pdfData() -> Data {
        let view = NSTextView(frame: NSRect(x: 0, y: 0, width: 468, height: 648))
        view.string = """
            Confidential Quarterly Review

            Demand for consumer AI tools grew steadily through the quarter, led by \
            productivity and creative applications on desktop and on mobile devices.
            Free tiers now drive most new sign ups across the category, which lowers \
            paid conversion for every vendor measured in this review.
            """
        return view.dataWithPDF(inside: view.bounds)
    }

    /// Writes a PDF, optionally padded past the size limit with trailing bytes
    /// that a reader ignores.
    private func writePDF(named name: String, padTo byteCount: Int? = nil) throws -> URL {
        var data = pdfData()
        if let byteCount, data.count < byteCount {
            data.append(Data(repeating: 0x20, count: byteCount - data.count))
        }
        let url = scratch.appendingPathComponent(name)
        try data.write(to: url)
        return url
    }

    private func writeLockedPDF(password: String) throws -> URL {
        let plainURL = scratch.appendingPathComponent("plain.pdf")
        try pdfData().write(to: plainURL)

        let document = try XCTUnwrap(PDFDocument(url: plainURL))
        let lockedURL = scratch.appendingPathComponent("locked.pdf")
        XCTAssertTrue(document.write(
            to: lockedURL,
            withOptions: [
                .userPasswordOption: password,
                .ownerPasswordOption: password
            ]
        ))
        return lockedURL
    }
}
