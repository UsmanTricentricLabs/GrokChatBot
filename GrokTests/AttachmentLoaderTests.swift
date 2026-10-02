//
//  AttachmentLoaderTests.swift
//  GrokTests
//
//  Created by Tricentric Labs on 02/10/2026.
//

import AppKit
import PDFKit
import XCTest
@testable import Grok

/// Covers the rules the composer promises: five megabytes, a clear word for a
/// corrupted file, and a password prompt rather than a failure for a locked one.
final class AttachmentLoaderTests: XCTestCase {

    private var scratch: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        scratch = FileManager.default.temporaryDirectory
            .appendingPathComponent("GrokAttachments-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let scratch { try? FileManager.default.removeItem(at: scratch) }
        scratch = nil
        try super.tearDownWithError()
    }

    // MARK: Text

    func testTextFileIsReadAsItsOwnContents() async throws {
        let url = try write("notes.txt", string: "Ship the composer on Thursday.")

        let attachment = try await AttachmentLoader.load(url: url)

        XCTAssertEqual(attachment.kind, .text)
        XCTAssertEqual(attachment.name, "notes.txt")
        XCTAssertTrue(attachment.text.contains("Ship the composer on Thursday."))
        XCTAssertTrue(attachment.hasText)
    }

    func testAttachedTextTravelsWithThePromptToTheModel() async throws {
        let url = try write("brief.txt", string: "The launch date is 14 November.")
        let attachment = try await AttachmentLoader.load(url: url)

        let message = ChatMessage(role: .user, text: "When do we launch?", attachments: [attachment])

        XCTAssertEqual(message.text, "When do we launch?")
        XCTAssertTrue(message.modelText.contains("The launch date is 14 November."))
        XCTAssertTrue(message.modelText.contains("brief.txt"))
        XCTAssertTrue(message.modelText.hasSuffix("When do we launch?"))
    }

    // MARK: Size

    func testAFileOverFiveMegabytesIsRefused() async throws {
        let url = scratch.appendingPathComponent("huge.txt")
        try Data(repeating: 0x41, count: AttachmentLoader.byteLimit + 1).write(to: url)

        await assertFails(url) { error in
            guard case .tooLarge(let name, _) = error else {
                return XCTFail("Expected a size failure, got \(error)")
            }
            XCTAssertEqual(name, "huge.txt")
        }
    }

    func testAFileExactlyAtTheLimitIsAccepted() async throws {
        let url = scratch.appendingPathComponent("limit.txt")
        try Data(repeating: 0x41, count: AttachmentLoader.byteLimit).write(to: url)

        let attachment = try await AttachmentLoader.load(url: url)

        XCTAssertEqual(attachment.byteCount, AttachmentLoader.byteLimit)
    }

    // MARK: Corruption

    func testBinaryRubbishInATextFileReadsAsCorrupted() async throws {
        let url = scratch.appendingPathComponent("broken.txt")
        try Data(repeating: 0x00, count: 2048).write(to: url)

        await assertFails(url) { error in
            guard case .corrupted = error else {
                return XCTFail("Expected a corruption failure, got \(error)")
            }
        }
    }

    func testATruncatedPDFReadsAsCorrupted() async throws {
        let url = scratch.appendingPathComponent("broken.pdf")
        try Data("%PDF-1.4 this file stops mid".utf8).write(to: url)

        await assertFails(url) { error in
            guard case .corrupted = error else {
                return XCTFail("Expected a corruption failure, got \(error)")
            }
        }
    }

    func testAnUnsupportedTypeIsRefusedByName() async throws {
        let url = try write("archive.zip", string: "not really an archive")

        await assertFails(url) { error in
            guard case .unsupportedType = error else {
                return XCTFail("Expected an unsupported-type failure, got \(error)")
            }
        }
    }

    // MARK: Passwords

    func testALockedPDFAsksForAPasswordRatherThanFailing() async throws {
        let url = try writeLockedPDF(password: "open-sesame")

        await assertFails(url) { error in
            XCTAssertEqual(error.lockedFileName, url.lastPathComponent)
        }
    }

    func testTheRightPasswordUnlocksTheDocument() async throws {
        let url = try writeLockedPDF(password: "open-sesame")

        let attachment = try await AttachmentLoader.load(url: url, password: "open-sesame")

        XCTAssertEqual(attachment.kind, .pdf)
        XCTAssertEqual(attachment.pageCount, 1)
        XCTAssertTrue(attachment.text.contains("quarterly figures"))
    }

    func testTheWrongPasswordIsReportedSoTheSheetCanStayOpen() async throws {
        let url = try writeLockedPDF(password: "open-sesame")

        await assertFails(url, password: "guess") { error in
            XCTAssertEqual(error, .incorrectPassword)
            XCTAssertNil(error.lockedFileName)
        }
    }

    // MARK: Kinds

    func testEachAcceptedExtensionMapsToItsKind() {
        XCTAssertEqual(AttachmentLoader.kind(of: URL(fileURLWithPath: "/tmp/a.txt")), .text)
        XCTAssertEqual(AttachmentLoader.kind(of: URL(fileURLWithPath: "/tmp/a.md")), .text)
        XCTAssertEqual(AttachmentLoader.kind(of: URL(fileURLWithPath: "/tmp/a.pdf")), .pdf)
        XCTAssertEqual(AttachmentLoader.kind(of: URL(fileURLWithPath: "/tmp/a.png")), .image)
        XCTAssertEqual(AttachmentLoader.kind(of: URL(fileURLWithPath: "/tmp/a.jpeg")), .image)
        XCTAssertNil(AttachmentLoader.kind(of: URL(fileURLWithPath: "/tmp/a.dmg")))
    }

    // MARK: Helpers

    private func write(_ name: String, string: String) throws -> URL {
        let url = scratch.appendingPathComponent(name)
        try Data(string.utf8).write(to: url)
        return url
    }

    private func writeLockedPDF(password: String) throws -> URL {
        let view = NSTextView(frame: NSRect(x: 0, y: 0, width: 468, height: 648))
        view.string = "Confidential: the quarterly figures are enclosed."
        let plainURL = scratch.appendingPathComponent("plain.pdf")
        try view.dataWithPDF(inside: view.bounds).write(to: plainURL)

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

    private func assertFails(
        _ url: URL,
        password: String? = nil,
        _ check: (AttachmentError) -> Void,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        do {
            _ = try await AttachmentLoader.load(url: url, password: password)
            XCTFail("Expected loading to fail", file: file, line: line)
        } catch let error as AttachmentError {
            check(error)
        } catch {
            XCTFail("Expected an AttachmentError, got \(error)", file: file, line: line)
        }
    }
}
