import AppKit
import SwiftUI

/// Editable native NSTextView with a visible, accessibility-friendly word
/// selection that follows the actual speech engine's event ranges.
struct WordTrackingEditor: NSViewRepresentable {
    @Binding var text: String
    @Environment(\.colorScheme) private var colorScheme
    let highlightedRange: NSRange?
    let editable: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        let editor = NSTextView()
        editor.isRichText = false
        editor.isEditable = true
        editor.isSelectable = true
        editor.allowsUndo = true
        editor.isAutomaticQuoteSubstitutionEnabled = false
        editor.isAutomaticTextReplacementEnabled = false
        editor.isAutomaticSpellingCorrectionEnabled = false
        editor.font = NSFont.systemFont(ofSize: 19, weight: .regular)
        editor.textColor = .labelColor
        editor.drawsBackground = false
        editor.textContainerInset = NSSize(width: 19, height: 20)
        editor.isVerticallyResizable = true
        editor.isHorizontallyResizable = false
        editor.autoresizingMask = [.width]
        editor.minSize = NSSize(width: 0, height: 0)
        editor.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude,
                                height: CGFloat.greatestFiniteMagnitude)
        editor.textContainer?.widthTracksTextView = true
        editor.string = text
        editor.delegate = context.coordinator
        scroll.documentView = editor
        context.coordinator.editor = editor
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let editor = scroll.documentView as? NSTextView else { return }
        if editor.string != text {
            editor.string = text
            context.coordinator.lastRange = nil
        }
        editor.isEditable = editable
        let coordinator = context.coordinator
        if coordinator.lastRange == highlightedRange { return }
        if let previous = coordinator.lastRange,
           NSMaxRange(previous) <= (editor.string as NSString).length {
            editor.layoutManager?.removeTemporaryAttribute(
                .backgroundColor, forCharacterRange: previous
            )
            editor.layoutManager?.removeTemporaryAttribute(
                .foregroundColor, forCharacterRange: previous
            )
        }
        let hadHighlight = coordinator.lastRange != nil
        coordinator.lastRange = highlightedRange
        if let range = highlightedRange,
           range.length > 0,
           NSMaxRange(range) <= (editor.string as NSString).length {
            let accent = StudioStyle.accentNS(for: colorScheme)
            editor.layoutManager?.addTemporaryAttributes([
                .backgroundColor: accent.withAlphaComponent(0.26),
                .foregroundColor: NSColor.labelColor
            ], forCharacterRange: range)
            editor.setSelectedRange(range)
            editor.scrollRangeToVisible(range)
        } else if hadHighlight {
            let position = min(editor.selectedRange().location,
                               (editor.string as NSString).length)
            editor.setSelectedRange(NSRange(location: position, length: 0))
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        @Binding var text: String
        weak var editor: NSTextView?
        var lastRange: NSRange?
        init(text: Binding<String>) { _text = text }

        func textDidChange(_ notification: Notification) {
            guard let editor, editor.isEditable else { return }
            text = editor.string
        }
    }
}
