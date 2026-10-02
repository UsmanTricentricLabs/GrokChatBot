//
//  ChatService.swift
//  Grok
//
//  Created by Tricentric Labs on 01/10/2026.
//

import Foundation

nonisolated protocol ChatService {
    /// Yields progressively longer snapshots of the answer, so the view can
    /// render a response as it arrives.
    ///
    /// `history` carries the earlier turns of the conversation; the app keeps
    /// the transcript locally and sends only what the request needs, because
    /// the Gateway stores nothing between calls.
    func respond(to prompt: String, history: [ChatMessage], system: String?)
        -> AsyncThrowingStream<[ResponseBlock], Error>
}

extension ChatService {
    func respond(to prompt: String, history: [ChatMessage] = []) -> AsyncThrowingStream<[ResponseBlock], Error> {
        respond(to: prompt, history: history, system: nil)
    }
}

/// Routes chat through the Central AI Gateway.
///
/// The Gateway returns a complete reply rather than a token stream, so the
/// answer is revealed word by word on arrival. That keeps the thinking,
/// streaming-caret and Stop behaviour the thread was built around.
nonisolated struct GatewayChatService: ChatService {

    /// The persona the app has always used for its answers.
    static let defaultSystemPrompt = """
        You are Grok, a direct and genuinely helpful assistant in a macOS app. \
        Answer in clear prose. Prefer short paragraphs. When a sequence of steps \
        genuinely helps, use a numbered list where each item opens with a short \
        bold lead phrase followed by one or two sentences. Do not use headings, \
        tables or emoji.
        """

    /// Delay between revealed words.
    var wordInterval: UInt64 = 12_000_000
    /// How many turns of history accompany a prompt.
    var historyLimit = 20

    private let client: GatewayClient

    init(client: GatewayClient = .shared) {
        self.client = client
    }

    func respond(
        to prompt: String,
        history: [ChatMessage],
        system: String?
    ) -> AsyncThrowingStream<[ResponseBlock], Error> {
        let turns = Self.turns(from: history, prompt: prompt, limit: historyLimit)
        let systemPrompt = system ?? Self.defaultSystemPrompt
        let interval = wordInterval
        let client = client

        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let response = try await client.chat(
                        messages: turns,
                        system: systemPrompt,
                        maxOutputTokens: 4096,
                        temperature: 0.7
                    )
                    try Task.checkCancellation()

                    let blocks = ResponseTextParser.blocks(from: response.message.content)
                    for snapshot in Self.reveal(blocks) {
                        try Task.checkCancellation()
                        continuation.yield(snapshot)
                        try await Task.sleep(nanoseconds: interval)
                    }
                    continuation.yield(blocks)
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// The transcript as Gateway turns, trimmed to the most recent exchanges
    /// and ending with the new prompt.
    private static func turns(from history: [ChatMessage], prompt: String, limit: Int) -> [GatewayChatTurn] {
        // `modelText` rather than `text`, so a turn that carried an attachment
        // still reaches the model with the file's contents attached to it.
        var turns = history
            .filter { !$0.isAwaitingResponse && !$0.modelText.isEmpty }
            .suffix(limit)
            .map { GatewayChatTurn(role: $0.role == .user ? .user : .assistant, content: $0.modelText) }

        // The prompt is appended only when the caller has not already placed it
        // in the transcript.
        if turns.last?.content != prompt {
            turns.append(GatewayChatTurn(role: .user, content: prompt))
        }
        return turns
    }

    /// Progressive snapshots of a finished answer: paragraphs fill word by
    /// word, lists one row at a time.
    private static func reveal(_ blocks: [ResponseBlock]) -> [[ResponseBlock]] {
        var snapshots: [[ResponseBlock]] = []
        var revealed: [ResponseBlock] = []

        for block in blocks {
            switch block {
            case .paragraph(let text):
                revealed.append(.paragraph(""))
                var current = ""
                for word in text.split(separator: " ", omittingEmptySubsequences: false) {
                    current += current.isEmpty ? String(word) : " \(word)"
                    revealed[revealed.count - 1] = .paragraph(current)
                    snapshots.append(revealed)
                }
            case .numberedList(let items):
                revealed.append(.numberedList([]))
                var shown: [NumberedItem] = []
                for item in items {
                    shown.append(item)
                    revealed[revealed.count - 1] = .numberedList(shown)
                    snapshots.append(revealed)
                }
            }
        }
        return snapshots
    }
}
