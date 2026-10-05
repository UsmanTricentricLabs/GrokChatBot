//
//  ImageViewModel.swift
//  Grok
//
//  Created by Tricentric Labs on 01/10/2026.
//

import AppKit
import os
import SwiftUI
import UniformTypeIdentifiers
internal import Combine

/// Drives the AI Image flow: prompt, style popover, generation and the
/// history that appears as sidebar thumbnails and the full gallery.
@MainActor
final class ImageViewModel: ObservableObject {

    @Published private(set) var images: [GeneratedImage] = []
    @Published var prompt: String = ""
    @Published var style: ImageStyle = .photographic
    @Published var ratio: ImageAspectRatio = .square
    @Published var isStylePopoverPresented = false
    /// Switches the main column between the latest result and the full grid.
    @Published var isGalleryPresented = false
    @Published private(set) var selectedImageID: UUID?
    /// The images made since the canvas was last reset, oldest first. They are
    /// shown as one running thread, so generating again adds to the session
    /// rather than replacing what is on screen.
    @Published private(set) var sessionImageIDs: [UUID] = []
    /// Set by "Create Image" in the sidebar: the screen returns to its empty
    /// state with a clear prompt, while the history behind it stays intact.
    @Published private(set) var isComposingNewImage = false

    private let service: ImageGenerationService
    private let history: ImageHistoryStore
    private var historyObserver: AnyCancellable?
    private var generationTask: Task<Void, Never>?

    init(
        service: ImageGenerationService = GatewayImageGenerationService(),
        history: ImageHistoryStore = .shared
    ) {
        self.service = service
        self.history = history
        self.images = history.load()

        // Every finished picture reaches the store. The pause lets a
        // generation settle so one image costs one write, not three.
        historyObserver = $images
            .dropFirst()
            .debounce(for: .seconds(0.4), scheduler: RunLoop.main)
            .sink { [weak self] images in
                self?.history.save(images)
            }
        _ = terminationObserver
    }

    /// Quitting does not wait for the debounce, so the last picture is written
    /// on the way out.
    private lazy var terminationObserver: Any = NotificationCenter.default.addObserver(
        forName: NSApplication.willTerminateNotification,
        object: nil,
        queue: .main
    ) { [weak self] _ in
        MainActor.assumeIsolated { self?.flushHistory() }
    }

    func flushHistory() {
        history.save(images)
    }

    // MARK: Derived state

    var isGenerating: Bool {
        images.contains { $0.state == .generating }
    }

    var canGenerate: Bool {
        !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// What the main column shows: the current session's thread, or the single
    /// image opened from the history.
    var threadImages: [GeneratedImage] {
        guard !isComposingNewImage else { return [] }

        // A thumbnail from an earlier session opens on its own; anything made
        // in this session stays part of the running thread.
        if let selectedImageID, !sessionImageIDs.contains(selectedImageID) {
            return images.filter { $0.id == selectedImageID }
        }
        return sessionImageIDs.compactMap { id in images.first { $0.id == id } }
    }

    var latestImage: GeneratedImage? { threadImages.last }

    var styleCaption: String { "\(style.title) · \(ratio.title)" }

    var hasHistory: Bool { !images.isEmpty }

    /// History grouped the way the gallery presents it.
    var groupedImages: [ImageGroup] {
        let calendar = Calendar.current
        let ready = images.filter { $0.state == .ready }
        let groups = Dictionary(grouping: ready) { calendar.startOfDay(for: $0.createdAt) }

        return groups.keys.sorted(by: >).map { day in
            ImageGroup(label: Self.label(for: day, calendar: calendar), images: groups[day] ?? [])
        }
    }

    // MARK: Generation

    /// Starts a fresh canvas, the way New Chat starts a fresh conversation:
    /// anything in flight is dropped, the prompt is cleared and the screen
    /// goes back to its empty state. The history is untouched.
    func startNewImage() {
        generationTask?.cancel()
        generationTask = nil
        images.removeAll { $0.state == .generating }

        sessionImageIDs.removeAll()
        selectedImageID = nil
        prompt = ""
        isStylePopoverPresented = false
        isGalleryPresented = false
        isComposingNewImage = true
    }

    func generate() {
        let text = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        let image = GeneratedImage(prompt: text, style: style, ratio: ratio)
        images.insert(image, at: 0)
        sessionImageIDs.append(image.id)
        selectedImageID = image.id
        isGalleryPresented = false
        isComposingNewImage = false
        prompt = ""

        generationTask?.cancel()
        generationTask = Task { [service, style, ratio] in
            do {
                let data = try await service.generate(
                    prompt: text,
                    style: style,
                    ratio: ratio,
                    reference: nil
                )
                guard !Task.isCancelled else { return }

                guard let artwork = NSImage(data: data) else {
                    update(image.id) { $0.state = .failed(AIErrorPresentation(GatewayError.temporary)) }
                    return
                }
                update(image.id) {
                    $0.image = artwork
                    $0.state = .ready
                }
            } catch is CancellationError {
                remove(image.id)
            } catch {
                update(image.id) { $0.state = .failed(AIErrorPresentation(error)) }
            }
        }
    }

    func stop() {
        generationTask?.cancel()
        generationTask = nil
        let abandoned = images.filter { $0.state == .generating }.map(\.id)
        for id in abandoned { remove(id) }
    }

    func regenerate(_ image: GeneratedImage) {
        prompt = image.prompt
        style = image.style
        ratio = image.ratio
        generate()
    }

    /// Edit Prompt: puts the text back into the input, as the design notes.
    func editPrompt(for image: GeneratedImage) {
        prompt = image.prompt
        style = image.style
        ratio = image.ratio
    }

    func select(_ image: GeneratedImage) {
        selectedImageID = image.id
        isGalleryPresented = false
        isComposingNewImage = false
    }

    func apply(style: ImageStyle, ratio: ImageAspectRatio) {
        self.style = style
        self.ratio = ratio
    }

    // MARK: Result actions

    /// Copies the picture itself, falling back to the prompt before it exists.
    func copy(_ image: GeneratedImage) {
        NSPasteboard.general.clearContents()
        if let artwork = image.image {
            NSPasteboard.general.writeObjects([artwork])
        } else {
            NSPasteboard.general.setString(image.prompt, forType: .string)
        }
    }

    func save(_ image: GeneratedImage) {
        guard let artwork = image.image else { return }

        let panel = NSSavePanel()
        panel.nameFieldStringValue = Self.fileName(for: image)
        panel.allowedContentTypes = [.png]
        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            try ArtworkExporter.writePNG(artwork, to: url)
        } catch {
            // Saving is a terminal action with no error slot in the design, so
            // a failure is reported rather than disappearing silently.
            GatewayError.log.error("Saving the image failed: \(error.localizedDescription, privacy: .public)")
            NSAlert(error: error).runModal()
        }
    }

    func share(_ image: GeneratedImage, from view: NSView?) {
        guard let view else { return }
        let items: [Any] = image.image.map { [$0] } ?? [image.prompt]
        NSSharingServicePicker(items: items).show(relativeTo: .zero, of: view, preferredEdge: .minY)
    }

    /// The name the save panel proposes.
    ///
    /// Every image carries the moment it was made, so saving a second one no
    /// longer lands on a file that is already there. Saving the *same* image
    /// twice still proposes the same name, which is what the replace warning
    /// is actually for.
    nonisolated static func fileName(for image: GeneratedImage) -> String {
        "Grok Image \(timestampFormatter.string(from: image.createdAt)).png"
    }

    /// Fixed locale and no colons, so the name is stable wherever the app runs
    /// and legal on every volume.
    private nonisolated static let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        return formatter
    }()

    // MARK: Private

    private func update(_ id: UUID, _ body: (inout GeneratedImage) -> Void) {
        guard let index = images.firstIndex(where: { $0.id == id }) else { return }
        body(&images[index])
    }

    private func remove(_ id: UUID) {
        images.removeAll { $0.id == id }
        sessionImageIDs.removeAll { $0 == id }
        if selectedImageID == id { selectedImageID = sessionImageIDs.last }
    }

    private static func label(for day: Date, calendar: Calendar) -> String {
        if calendar.isDateInToday(day) { return "Today" }
        if calendar.isDateInYesterday(day) { return "Yesterday" }

        let formatter = DateFormatter()
        formatter.dateFormat = "d MMMM"
        return formatter.string(from: day)
    }
}
