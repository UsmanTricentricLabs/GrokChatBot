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
    ///
    /// Answers are rendered with AIFormattingKit, so the model is free to use
    /// the Markdown that formatter draws: headings, lists, tables and fenced
    /// code with a language tag.
    static let defaultSystemPrompt = """
        You are Grok, a direct and genuinely helpful assistant in a macOS app. \
        Answer in clear prose with short paragraphs. Use Markdown when it helps: \
        headings, bullet or numbered lists with a short bold lead phrase per \
        item, tables for comparisons, and fenced code blocks tagged with their \
        language. Do not use emoji.
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

                    let answer = response.message.content.trimmingCharacters(in: .whitespacesAndNewlines)
                    for snapshot in Self.reveal(answer) {
                        try Task.checkCancellation()
                        continuation.yield(snapshot)
                        try await Task.sleep(nanoseconds: interval)
                    }
                    continuation.yield([.markdown(answer)])
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

    /// Progressive snapshots of a finished answer: the Markdown fills word by
    /// word, so the formatter lays out more of the reply on every tick.
    private static func reveal(_ answer: String) -> [[ResponseBlock]] {
        var snapshots: [[ResponseBlock]] = []
        var revealed = ""

        // Splitting on spaces alone keeps the line breaks inside each token, so
        // rejoining them reproduces the answer's Markdown exactly.
        for word in answer.split(separator: " ", omittingEmptySubsequences: false) {
            revealed += revealed.isEmpty ? String(word) : " \(word)"
            snapshots.append([.markdown(revealed)])
        }
        return snapshots
    }
}
