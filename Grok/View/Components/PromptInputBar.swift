//
//  PromptInputBar.swift
//  Grok
//
//  Created by Tricentric Labs on 01/10/2026.
//

import SwiftUI
import UniformTypeIdentifiers

/// The shared composer: an attach button, the attached files, a growing prompt
/// field and a set of trailing actions supplied by the flow using it.
///
/// It sits over the content on a gradient so text scrolls away cleanly
/// underneath, exactly as the design shows.
struct PromptInputBar<Actions: View>: View {
    @Binding var text: String
    let placeholder: String
    let onSubmit: () -> Void

    var onAttach: (() -> Void)?
    /// Files already attached to the next prompt, drawn as chips above the field.
    var attachments: [ChatAttachment] = []
    var onRemoveAttachment: ((ChatAttachment) -> Void)?
    /// Called when files are dropped on the bar.
    var onDropFiles: (([URL]) -> Void)?

    /// The trailing controls the flow supplies — microphone, send, a style
    /// pill. Declared last so call sites keep passing it as a trailing closure.
    @ViewBuilder let actions: () -> Actions

    @State private var fieldHeight: CGFloat = GrokTextStyle.body.lineHeight
    @State private var isFocused = false
    @State private var isDropTargeted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !attachments.isEmpty {
                AttachmentChipRow(attachments: attachments, onRemove: onRemoveAttachment)
                    .padding(.horizontal, 4)
            }

            HStack(alignment: .bottom, spacing: 10) {
                Button {
                    onAttach?()
                } label: {
                    GrokPlateIcon(GrokAsset.attach, size: GrokMetrics.inputButton)
                        .frame(width: 50, height: GrokMetrics.inputButton)
                }
                .buttonStyle(GrokButtonStyle())
                .help("chat.attachHelp".localized)

                GrowingTextView(
                    text: $text,
                    placeholder: placeholder,
                    onSubmit: onSubmit,
                    onHeightChange: { fieldHeight = $0 },
                    onFocusChange: { isFocused = $0 }
                )
                .frame(height: fieldHeight)
                .padding(.vertical, 12)

                actions()
            }
        }
        .padding(12)
        .frame(minHeight: GrokMetrics.inputMinHeight)
        .background(
            RoundedRectangle(cornerRadius: GrokMetrics.cardRadius, style: .continuous)
                .fill(GrokColor.white4)
        )
        .decorativeBorder(
            borderColor,
            width: isDropTargeted ? 2 : 1,
            cornerRadius: GrokMetrics.cardRadius
        )
        .animation(.easeOut(duration: 0.15), value: isFocused)
        .animation(.easeOut(duration: 0.15), value: fieldHeight)
        .animation(.easeOut(duration: 0.15), value: isDropTargeted)
        .animation(.easeOut(duration: 0.15), value: attachments)
        .onDrop(of: [UTType.fileURL], isTargeted: onDropFiles == nil ? nil : $isDropTargeted) { providers in
            guard let onDropFiles else { return false }
            return Self.loadURLs(from: providers, then: onDropFiles)
        }
    }

    private var borderColor: Color {
        if isDropTargeted { return GrokColor.black4 }
        return isFocused ? GrokColor.white5 : .clear
    }

    /// Collects the dropped file URLs, then hands them over on the main actor.
    private static func loadURLs(
        from providers: [NSItemProvider],
        then handle: @escaping ([URL]) -> Void
    ) -> Bool {
        let fileProviders = providers.filter { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }
        guard !fileProviders.isEmpty else { return false }

        let collector = DroppedURLCollector(expected: fileProviders.count, handle: handle)
        for provider in fileProviders {
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                Task { @MainActor in collector.add(url) }
            }
        }
        return true
    }
}

/// Gathers the URLs a multi-file drop delivers one at a time, and reports them
/// once the last one has arrived.
@MainActor
private final class DroppedURLCollector {
    private let expected: Int
    private let handle: ([URL]) -> Void
    private var urls: [URL] = []
    private var received = 0

    init(expected: Int, handle: @escaping ([URL]) -> Void) {
        self.expected = expected
        self.handle = handle
    }

    func add(_ url: URL?) {
        if let url { urls.append(url) }
        received += 1
        guard received == expected else { return }
        if !urls.isEmpty { handle(urls) }
    }
}

/// The gradient plate the composer floats on.
struct PromptInputBarContainer<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .padding(.horizontal, 40)
            .padding(.vertical, 24)
            .background(
                LinearGradient(
                    stops: [
                        .init(color: GrokColor.white3.opacity(0), location: 0),
                        .init(color: GrokColor.white3, location: 0.28)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
    }
}

/// Send, or Stop while a response is in flight.
struct SendButton: View {
    let isEnabled: Bool
    let isStreaming: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                if isStreaming {
                    Circle().fill(GrokColor.black1)
                    SymbolIcon("stop.fill", size: 18, color: .white)
                } else {
                    GrokPlateIcon(isEnabled ? GrokAsset.send : GrokAsset.sendDisabled,
                                  size: GrokMetrics.inputButton)
                }
            }
            .frame(width: GrokMetrics.inputButton, height: GrokMetrics.inputButton)
        }
        .buttonStyle(GrokButtonStyle())
        .disabled(!isEnabled && !isStreaming)
        .help(isStreaming ? "common.stop".localized : "common.send".localized)
    }
}

/// The microphone button beside Send.
///
/// It owns the whole dictation flow: asking for permission on first press,
/// streaming what it hears into the prompt field, and offering System Settings
/// when permission has already been refused.
struct MicrophoneButton: View {
    @Binding var text: String

    @StateObject private var dictation = DictationController()
    /// What the field held when dictation started, so speech appends rather
    /// than replaces what the user already typed.
    @State private var baseText = ""
    @State private var isPulsing = false

    var body: some View {
        Button {
            if dictation.isListening {
                dictation.stop()
            } else {
                baseText = text
                Task { await dictation.start() }
            }
        } label: {
            ZStack {
                if dictation.isListening {
                    Circle()
                        .fill(GrokColor.black1)
                    Circle()
                        .strokeBorder(GrokColor.error.opacity(isPulsing ? 0.15 : 0.5), lineWidth: 3)
                    SymbolIcon("waveform", size: 20, weight: .medium, color: .white)
                } else {
                    GrokPlateIcon(GrokAsset.microphone, size: GrokMetrics.inputButton)
                }
            }
            .frame(width: GrokMetrics.inputButton, height: GrokMetrics.inputButton)
        }
        .buttonStyle(GrokButtonStyle())
        .help(dictation.isListening ? "dictation.stop".localized : "dictation.start".localized)
        .onAppear {
            dictation.onTranscript = { transcript in
                text = Self.joined(baseText, transcript)
            }
        }
        .onDisappear { dictation.stop() }
        .onChange(of: dictation.isListening) { listening in
            isPulsing = listening
        }
        .animation(
            dictation.isListening
                ? .easeInOut(duration: 0.7).repeatForever(autoreverses: true)
                : .default,
            value: isPulsing
        )
        .alert(item: $dictation.permissionIssue) { issue in
            if let settingsURL = issue.settingsURL {
                return Alert(
                    title: Text(issue.title),
                    message: Text(issue.message),
                    primaryButton: .default(Text("common.openSettings".localized)) {
                        NSWorkspace.shared.open(settingsURL)
                    },
                    secondaryButton: .cancel(Text("common.notNow".localized))
                )
            }
            return Alert(
                title: Text(issue.title),
                message: Text(issue.message),
                dismissButton: .default(Text("common.ok".localized))
            )
        }
    }

    private static func joined(_ base: String, _ transcript: String) -> String {
        guard !base.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return transcript }
        guard !transcript.isEmpty else { return base }
        return base.hasSuffix(" ") ? base + transcript : base + " " + transcript
    }
}
