//
//  HomeScreen.swift
//  Grok
//
//  Created by Tricentric Labs on 01/10/2026.
//

import SwiftUI

/// The Chat flow: an empty home with prompt starters that becomes a thread
/// once a conversation is under way.
struct HomeScreen: View {

    @ObservedObject var screenSwitchVM: ScreenSwitchViewModel
    @ObservedObject var chatVM: ChatViewModel
    var containerWidth: CGFloat
    var containerHeight: CGFloat
    var showsSidebarToggle: Bool = false

    /// Computed, not stored: a stored constant would capture its copy in the
    /// language the app launched in and keep it after a language change.
    private static var starters: [SuggestionStarter] { [
        SuggestionStarter(
            title: "starter.code.title".localized,
            description: "starter.code.detail".localized,
            icon: .asset(GrokAsset.codeAndDebug),
            prompt: "starter.code.prompt".localized
        ),
        SuggestionStarter(
            title: "starter.write.title".localized,
            description: "starter.write.detail".localized,
            icon: .asset(GrokAsset.writeAndSummarize),
            prompt: "starter.write.prompt".localized
        ),
        SuggestionStarter(
            title: "starter.data.title".localized,
            description: "starter.data.detail".localized,
            icon: .asset(GrokAsset.dataInsights),
            prompt: "starter.data.prompt".localized
        )
    ] }

    var body: some View {
        VStack(spacing: 0) {
            HeaderBar(showsSidebarToggle: showsSidebarToggle) {
                screenSwitchVM.isSidebarPresented.toggle()
            }

            ZStack(alignment: .bottom) {
                if chatVM.messages.isEmpty {
                    emptyState
                } else {
                    thread
                }

                PromptInputBarContainer {
                    VStack(spacing: 10) {
                        if let message = chatVM.attachmentError {
                            AttachmentErrorBanner(message: message) {
                                chatVM.attachmentError = nil
                            }
                            .transition(.opacity)
                        }

                        PromptInputBar(
                            text: $chatVM.draft,
                            placeholder: "common.askAnything".localized,
                            onSubmit: chatVM.send,
                            onAttach: chatVM.chooseAttachments,
                            attachments: chatVM.attachments,
                            onRemoveAttachment: chatVM.removeAttachment,
                            onDropFiles: chatVM.attach
                        ) {
                            HStack(spacing: 6) {
                                MicrophoneButton(text: $chatVM.draft)
                                SendButton(
                                    isEnabled: chatVM.canSend && !chatVM.isReadingAttachment,
                                    isStreaming: chatVM.isResponding
                                ) {
                                    if chatVM.isResponding {
                                        chatVM.stop()
                                    } else {
                                        chatVM.send()
                                    }
                                }
                            }
                        }
                    }
                    .animation(.easeOut(duration: 0.15), value: chatVM.attachmentError)
                }
            }
        }
        .background(GrokColor.white3)
        .sheet(item: $chatVM.passwordRequest) { request in
            AttachmentPasswordSheet(
                fileName: request.name,
                errorMessage: request.errorMessage,
                isUnlocking: request.isUnlocking,
                onUnlock: chatVM.submitPassword,
                onCancel: chatVM.cancelPasswordRequest
            )
        }
    }

    // MARK: Slots

    private var emptyState: some View {
        CenteredScrollView {
            VStack(spacing: isCompact ? 32 : 60) {
                HeroHeader(
                    title: "home.hero.title".localized,
                    subtitle: "home.hero.subtitle".localized,
                    isCompact: isCompact
                )

                SuggestionRow(starters: Self.starters, availableWidth: containerWidth - 80) { starter in
                    chatVM.draft = starter.prompt
                }
            }
        }
    }

    /// Short windows tighten the hero so it stays clear of the composer.
    private var isCompact: Bool {
        containerHeight < 700
    }

    private var thread: some View {
        ScrollViewReader { scroller in
            ScrollView(.vertical, showsIndicators: true) {
                VStack(alignment: .trailing, spacing: 16) {
                    ForEach(chatVM.messages) { message in
                        messageRow(message)
                            .id(message.id)
                    }
                    Color.clear
                        .frame(height: 1)
                        .id(Self.threadBottomID)
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.horizontal, GrokMetrics.contentPadding)
                .padding(.top, 16)
                .padding(.bottom, 136)
            }
            .onChange(of: chatVM.messages) { _ in
                withAnimation(.easeOut(duration: 0.2)) {
                    scroller.scrollTo(Self.threadBottomID, anchor: .bottom)
                }
            }
        }
    }

    @ViewBuilder
    private func messageRow(_ message: ChatMessage) -> some View {
        switch message.role {
        case .user:
            UserMessageBubble(text: message.text, attachments: message.attachments)
                .frame(maxWidth: .infinity, alignment: .trailing)
        case .assistant:
            AssistantMessageView(
                message: message,
                onCopy: { chatVM.copy(message) },
                onSpeak: { chatVM.speak(message) },
                onRegenerate: chatVM.regenerateLastResponse,
                onRetry: chatVM.retryLastResponse
            )
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private static let threadBottomID = "thread-bottom"
}
