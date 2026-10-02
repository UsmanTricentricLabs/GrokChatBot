//
//  GrowingTextView.swift
//  Grok
//
//  Created by Tricentric Labs on 01/10/2026.
//

import AppKit
import SwiftUI

/// The prompt field: a transparent text view that grows with its content up
/// to a line limit, then scrolls. Return submits, Shift+Return inserts a
/// newline — the convention the design's input bar implies.
struct GrowingTextView: NSViewRepresentable {
    @Binding var text: String
    var placeholder: String
    var maxLines: Int = GrokMetrics.inputMaxLines
    var onSubmit: () -> Void
    /// Reports the height the content wants, so the bar can grow upward.
    var onHeightChange: (CGFloat) -> Void
    var onFocusChange: (Bool) -> Void

    private var font: NSFont { .systemFont(ofSize: GrokTextStyle.body.size) }
    private var lineHeight: CGFloat { GrokTextStyle.body.lineHeight }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let textView = SubmittingTextView()
        textView.delegate = context.coordinator
        textView.onSubmit = onSubmit
        textView.onFocusChange = onFocusChange
        textView.font = font
        textView.drawsBackground = false
        textView.isRichText = false
        textView.allowsUndo = true
        textView.textContainerInset = .zero
        textView.textContainer?.lineFragmentPadding = 0
        textView.textColor = .labelColor
        textView.insertionPointColor = .labelColor
        textView.defaultParagraphStyle = Self.paragraphStyle(lineHeight: lineHeight)
        textView.typingAttributes = [
            .font: font,
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: Self.paragraphStyle(lineHeight: lineHeight)
        ]
        textView.placeholderString = placeholder

        let scrollView = NSScrollView()
        scrollView.documentView = textView
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.verticalScrollElasticity = .none
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? SubmittingTextView else { return }

        context.coordinator.parent = self
        textView.onSubmit = onSubmit
        textView.onFocusChange = onFocusChange

        if textView.string != text {
            textView.string = text
            // A prompt starter or Edit Prompt fills the field from outside, so
            // the caret goes to the end — otherwise what the user types next
            // lands in front of the text that was just put there.
            textView.setSelectedRange(NSRange(location: (text as NSString).length, length: 0))

            if !text.isEmpty,
               let window = textView.window,
               window.firstResponder !== textView {
                window.makeFirstResponder(textView)
            }
        }
        if textView.placeholderString != placeholder {
            textView.placeholderString = placeholder
        }

        DispatchQueue.main.async {
            onHeightChange(contentHeight(of: textView))
        }
    }

    /// Measured content height, clamped to the line limit.
    private func contentHeight(of textView: NSTextView) -> CGFloat {
        guard let layoutManager = textView.layoutManager, let container = textView.textContainer else {
            return lineHeight
        }
        layoutManager.ensureLayout(for: container)
        let used = layoutManager.usedRect(for: container).height
        return min(max(used, lineHeight), lineHeight * CGFloat(maxLines))
    }

    private static func paragraphStyle(lineHeight: CGFloat) -> NSMutableParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.minimumLineHeight = lineHeight
        style.maximumLineHeight = lineHeight
        return style
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: GrowingTextView

        init(_ parent: GrowingTextView) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
        }
    }
}

/// An `NSTextView` that submits on Return, draws a placeholder and reports
/// focus so the input bar can show its ring.
private final class SubmittingTextView: NSTextView {
    var onSubmit: (() -> Void)?
    var onFocusChange: ((Bool) -> Void)?

    var placeholderString: String = "" {
        didSet { needsDisplay = true }
    }

    override func keyDown(with event: NSEvent) {
        let isReturn = event.keyCode == 36 || event.keyCode == 76
        let hasShift = event.modifierFlags.contains(.shift)

        if isReturn, !hasShift {
            onSubmit?()
            return
        }
        super.keyDown(with: event)
    }

    override func becomeFirstResponder() -> Bool {
        onFocusChange?(true)
        return super.becomeFirstResponder()
    }

    override func resignFirstResponder() -> Bool {
        onFocusChange?(false)
        return super.resignFirstResponder()
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard string.isEmpty, !placeholderString.isEmpty else { return }

        let attributes: [NSAttributedString.Key: Any] = [
            .font: font ?? NSFont.systemFont(ofSize: GrokTextStyle.body.size),
            .foregroundColor: NSColor.placeholderTextColor
        ]
        let size = placeholderString.size(withAttributes: attributes)
        let origin = NSPoint(x: 0, y: (GrokTextStyle.body.lineHeight - size.height) / 2)
        placeholderString.draw(at: origin, withAttributes: attributes)
    }
}
