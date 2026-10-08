//
//  DictationController.swift
//  Grok
//
//  Created by Tricentric Labs on 02/10/2026.
//

import AVFoundation
import AppKit
import Speech
import SwiftUI
internal import Combine

/// Why dictation cannot start, and where the user has to go to fix it.
nonisolated enum DictationPermissionIssue: Identifiable, Equatable {
    case microphoneDenied
    case speechDenied
    case unavailable(String)

    var id: String {
        switch self {
        case .microphoneDenied: return "microphone"
        case .speechDenied: return "speech"
        case .unavailable(let reason): return "unavailable-\(reason)"
        }
    }

    var title: String {
        switch self {
        case .microphoneDenied: return "dictation.mic.title".localized
        case .speechDenied: return "dictation.speech.title".localized
        case .unavailable: return "dictation.unavailable.title".localized
        }
    }

    var message: String {
        switch self {
        case .microphoneDenied:
            return "dictation.mic.detail".localized
        case .speechDenied:
            return "dictation.speech.detail".localized
        case .unavailable(let reason):
            return reason
        }
    }

    /// The Privacy pane to open, for the two issues System Settings can fix.
    var settingsURL: URL? {
        switch self {
        case .microphoneDenied:
            return URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")
        case .speechDenied:
            return URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_SpeechRecognition")
        case .unavailable:
            return nil
        }
    }
}

/// Turns speech into text for the composer.
///
/// Permission is asked for the first time the microphone button is pressed —
/// microphone first, then speech recognition — and only then does the audio
/// engine start. A refusal is not a dead end: the system asks again while the
/// answer is still undecided, and once it is settled the alert offers to open
/// the exact Privacy pane that grants it.
@MainActor
final class DictationController: NSObject, ObservableObject {

    /// True while audio is being captured.
    @Published private(set) var isListening = false
    /// What has been heard so far in this session.
    @Published private(set) var transcript = ""
    /// Set when dictation cannot start; the view shows it as an alert.
    @Published var permissionIssue: DictationPermissionIssue?

    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private let audioEngine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?

    /// Called with the full transcript each time it grows.
    var onTranscript: ((String) -> Void)?

    // MARK: Control

    func toggle() {
        if isListening {
            stop()
        } else {
            Task { await start() }
        }
    }

    func start() async {
        guard !isListening else { return }

        guard await ensureMicrophoneAccess() else {
            permissionIssue = .microphoneDenied
            return
        }
        guard await ensureSpeechAccess() else {
            permissionIssue = .speechDenied
            return
        }
        guard let recognizer, recognizer.isAvailable else {
            permissionIssue = .unavailable(
                "dictation.speech.unavailable".localized
            )
            return
        }

        do {
            try beginCapture(with: recognizer)
        } catch {
            stop()
            permissionIssue = .unavailable(
                "dictation.mic.failed".localized
            )
        }
    }

    func stop() {
        guard isListening || task != nil else { return }

        audioEngine.inputNode.removeTap(onBus: 0)
        if audioEngine.isRunning { audioEngine.stop() }
        request?.endAudio()
        task?.cancel()
        request = nil
        task = nil
        isListening = false
    }

    /// Clears the session so the next dictation starts from an empty slate.
    func reset() {
        stop()
        transcript = ""
    }

    /// Opens the Privacy pane that grants the refused permission.
    func openSettings(for issue: DictationPermissionIssue) {
        guard let url = issue.settingsURL else { return }
        NSWorkspace.shared.open(url)
    }

    // MARK: Capture

    private func beginCapture(with recognizer: SFSpeechRecognizer) throws {
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        self.request = request
        transcript = ""

        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        guard format.channelCount > 0 else { throw DictationStartError.noInput }

        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            request.append(buffer)
        }

        audioEngine.prepare()
        try audioEngine.start()
        isListening = true

        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if let result {
                    self.transcript = result.bestTranscription.formattedString
                    self.onTranscript?(self.transcript)
                    if result.isFinal { self.stop() }
                } else if error != nil {
                    self.stop()
                }
            }
        }
    }

    private enum DictationStartError: Error {
        case noInput
    }

    // MARK: Permissions

    /// Asks for the microphone while the answer is still undecided; a settled
    /// refusal is reported so the caller can offer System Settings.
    private func ensureMicrophoneAccess() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return true
        case .notDetermined:
            return await AVCaptureDevice.requestAccess(for: .audio)
        default:
            return false
        }
    }

    private func ensureSpeechAccess() async -> Bool {
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized:
            return true
        case .notDetermined:
            return await withCheckedContinuation { continuation in
                SFSpeechRecognizer.requestAuthorization { status in
                    continuation.resume(returning: status == .authorized)
                }
            }
        default:
            return false
        }
    }
}
