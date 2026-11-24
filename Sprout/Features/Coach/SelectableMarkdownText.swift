import SwiftUI
import UIKit

// A coach reply whose text can be selected by range.
//
// On the iOS versions this app supports (18 and 26), SwiftUI's `.textSelection(.enabled)`
// offers Copy and Share for the WHOLE text of a `Text` and nothing else: no handles, no
// range (Apple: "These menu items operate on the entire contents of the Text view"; range
// selection for `Text` arrives in iOS 27). Selecting a sentence therefore needs a
// `UITextView`. This file lays `MarkdownMessage`'s blocks out as one attributed string in
// one non-editable text view, so a selection can run across paragraphs, list items and
// headings, and adds "Ask about this" to the system edit menu.
//
// Sources and what was measured are in `docs/chat-standards.md`, section 2.

// MARK: - Blocks → attributed string

enum MarkdownAttributedText {

    /// The colours and the text size the string is built for.
    struct Style: Equatable {
        var text: UIColor
        var accent: UIColor
        var rule: UIColor
        var sizeCategory: UIContentSizeCategory

        @MainActor
        static func current(text: Color, sizeCategory: UIContentSizeCategory) -> Style {
            Style(text: UIColor(text), accent: UIColor(Theme.brand), rule: UIColor(Theme.divider),
                  sizeCategory: sizeCategory)
        }

        var traits: UITraitCollection { UITraitCollection(preferredContentSizeCategory: sizeCategory) }
        var body: UIFont { UIFont.preferredFont(forTextStyle: .body, compatibleWith: traits) }
        var headline: UIFont { UIFont.preferredFont(forTextStyle: .headline, compatibleWith: traits) }
    }

    /// Space between blocks, the same 6 pt `MarkdownMessage` puts between its rows.
    static let blockSpacing: CGFloat = 6
    /// Indent per list nesting level, as in `MarkdownMessage`.
    static let indentStep: CGFloat = 14
    /// Gap between a list marker and its text, as in `MarkdownMessage`.
    static let markerGap: CGFloat = 8

    /// Inside one paragraph a soft line break must not start a new paragraph (which would
    /// add block spacing), so it is stored as a line separator. `plainText` turns it back.
    static let softBreak = "\u{2028}"

    static func build(_ markdown: String, style: Style) -> NSAttributedString {
        build(blocks: MarkdownMessage.parse(markdown), style: style)
    }

    static func build(blocks: [MarkdownMessage.Block], style: Style) -> NSAttributedString {
        let out = NSMutableAttributedString()
        for (index, block) in blocks.enumerated() {
            let isLast = index == blocks.count - 1
            let piece: NSMutableAttributedString
            let paragraph = NSMutableParagraphStyle()
            // TextKit puts the font's leading under every line, the last line of a paragraph
            // included; SwiftUI's `Text` leaves it off the last line. Taking it out of the
            // gap keeps the blocks exactly as far apart as `MarkdownMessage` draws them.
            var leading = style.body.leading
            var ruleFont: UIFont?

            switch block {
            case .paragraph(let text):
                piece = inline(text.replacingOccurrences(of: "\n", with: softBreak), font: style.body, style: style)

            case .heading(let text):
                piece = inline(text, font: style.headline, style: style)
                paragraph.paragraphSpacingBefore = index == 0 ? 0 : 1
                leading = style.headline.leading

            case .bullet(let indent, let text):
                let markerFont = bold(style.body)
                piece = listItem(marker: "•", markerFont: markerFont, indent: indent, text: text,
                                 style: style, paragraph: paragraph)

            case .numbered(let indent, let number, let text):
                let markerFont = monospacedDigits(semibold(style.body))
                piece = listItem(marker: "\(number).", markerFont: markerFont, indent: indent, text: text,
                                 style: style, paragraph: paragraph)

            case .rule:
                let attachment = RuleAttachment(color: style.rule)
                piece = NSMutableAttributedString(attachment: attachment)
                // The line is exactly as tall as the rule, not as tall as a line of text.
                ruleFont = UIFont.systemFont(ofSize: 1)
                paragraph.minimumLineHeight = RuleAttachment.height
                paragraph.maximumLineHeight = RuleAttachment.height
                leading = 0
            }

            paragraph.paragraphSpacing = isLast ? 0 : max(0, blockSpacing - leading)
            let breakFont = ruleFont ?? style.body
            if let ruleFont {
                piece.addAttribute(.font, value: ruleFont, range: NSRange(location: 0, length: piece.length))
            }
            piece.addAttribute(.paragraphStyle, value: paragraph, range: NSRange(location: 0, length: piece.length))
            out.append(piece)
            if !isLast {
                out.append(NSAttributedString(string: "\n", attributes: [.font: breakFont, .paragraphStyle: paragraph]))
            }
        }
        return out
    }

    private static func listItem(marker: String, markerFont: UIFont, indent: Int, text: String,
                                 style: Style, paragraph: NSMutableParagraphStyle) -> NSMutableAttributedString {
        let leading = CGFloat(indent) * indentStep
        let markerWidth = ceil((marker as NSString).size(withAttributes: [.font: markerFont]).width)
        let textStart = leading + markerWidth + markerGap
        paragraph.firstLineHeadIndent = leading
        paragraph.headIndent = textStart
        paragraph.tabStops = [NSTextTab(textAlignment: .left, location: textStart)]
        paragraph.defaultTabInterval = textStart

        let piece = NSMutableAttributedString(string: marker + "\t",
                                              attributes: [.font: markerFont, .foregroundColor: style.accent])
        piece.append(inline(text, font: style.body, style: style))
        return piece
    }

    /// Inline markdown (bold, italic, code, strikethrough, links) in one block, on `font`.
    static func inline(_ source: String, font: UIFont, style: Style) -> NSMutableAttributedString {
        let parsed = MarkdownMessage.inline(source)
        let out = NSMutableAttributedString()
        for run in parsed.runs {
            let text = String(parsed[run.range].characters)
            var runFont = font
            var attributes: [NSAttributedString.Key: Any] = [.foregroundColor: style.text]
            if let intent = run.inlinePresentationIntent {
                if intent.contains(.code) {
                    runFont = UIFont.monospacedSystemFont(ofSize: font.pointSize, weight: .regular)
                }
                var traits = runFont.fontDescriptor.symbolicTraits
                if intent.contains(.stronglyEmphasized) { traits.insert(.traitBold) }
                if intent.contains(.emphasized) { traits.insert(.traitItalic) }
                if traits != runFont.fontDescriptor.symbolicTraits,
                   let descriptor = runFont.fontDescriptor.withSymbolicTraits(traits) {
                    runFont = UIFont(descriptor: descriptor, size: runFont.pointSize)
                }
                if intent.contains(.strikethrough) {
                    attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
                }
            }
            if let link = run.link { attributes[.link] = link }
            attributes[.font] = runFont
            out.append(NSAttributedString(string: text, attributes: attributes))
        }
        return out
    }

    private static func bold(_ font: UIFont) -> UIFont {
        guard let descriptor = font.fontDescriptor.withSymbolicTraits(
            font.fontDescriptor.symbolicTraits.union(.traitBold)) else { return font }
        return UIFont(descriptor: descriptor, size: font.pointSize)
    }

    private static func semibold(_ font: UIFont) -> UIFont {
        let descriptor = font.fontDescriptor.addingAttributes([
            .traits: [UIFontDescriptor.TraitKey.weight: UIFont.Weight.semibold]])
        return UIFont(descriptor: descriptor, size: font.pointSize)
    }

    private static func monospacedDigits(_ font: UIFont) -> UIFont {
        let descriptor = font.fontDescriptor.addingAttributes([
            .featureSettings: [[UIFontDescriptor.FeatureKey.type: kNumberSpacingType,
                                UIFontDescriptor.FeatureKey.selector: kMonospacedNumbersSelector]]])
        return UIFont(descriptor: descriptor, size: font.pointSize)
    }

    /// TextKit puts the font's leading under the last line too; SwiftUI's `Text` does not.
    /// The reply view takes this much off its bottom edge with negative padding, so a
    /// bubble is exactly as tall as `MarkdownMessage` makes it. (Making the text view itself
    /// shorter does not work: a text view that cannot scroll draws only the lines that fit
    /// its container, so the reply loses its last line.)
    static func trailingLeading(_ sizeCategory: UIContentSizeCategory) -> CGFloat {
        UIFont.preferredFont(forTextStyle: .body,
                             compatibleWith: UITraitCollection(preferredContentSizeCategory: sizeCategory)).leading
    }

    /// A length rounded up to a whole pixel.
    static func pixelCeil(_ value: CGFloat, scale: CGFloat) -> CGFloat {
        let scale = max(1, scale)
        return ceil(value * scale - 0.01) / scale
    }

    /// What a copied or quoted range should read as: soft breaks are line breaks again, a
    /// list marker is followed by a space rather than a tab, and a rule is `---`.
    static func plainText(_ selected: String) -> String {
        selected
            .replacingOccurrences(of: softBreak, with: "\n")
            .replacingOccurrences(of: "\t", with: " ")
            .replacingOccurrences(of: "\u{FFFC}", with: "---")
    }
}

/// A thematic break: one hairline as wide as the line it sits on.
final class RuleAttachment: NSTextAttachment {
    private let color: UIColor
    static let lineHeight: CGFloat = 1
    static let verticalPadding: CGFloat = 2

    init(color: UIColor) {
        self.color = color
        super.init(data: nil, ofType: nil)
        image = UIImage()
    }

    required init?(coder: NSCoder) { nil }

    /// The hairline plus the 2 pt `MarkdownMessage` pads it with above and below.
    static var height: CGFloat { lineHeight + 2 * verticalPadding }

    private func bounds(lineWidth: CGFloat) -> CGRect {
        CGRect(x: 0, y: 0, width: max(1, lineWidth), height: Self.height)
    }

    // TextKit 1
    override func attachmentBounds(for textContainer: NSTextContainer?, proposedLineFragment lineFrag: CGRect,
                                   glyphPosition position: CGPoint, characterIndex charIndex: Int) -> CGRect {
        bounds(lineWidth: lineFrag.width - position.x)
    }

    // TextKit 2
    override func attachmentBounds(for attributes: [NSAttributedString.Key: Any], location: any NSTextLocation,
                                   textContainer: NSTextContainer?, proposedLineFragment: CGRect,
                                   position: CGPoint) -> CGRect {
        bounds(lineWidth: proposedLineFragment.width - position.x)
    }

    override func image(forBounds imageBounds: CGRect, textContainer: NSTextContainer?,
                        characterIndex charIndex: Int) -> UIImage? {
        let size = CGSize(width: max(1, imageBounds.width), height: max(1, imageBounds.height))
        return UIGraphicsImageRenderer(size: size).image { context in
            color.setFill()
            context.fill(CGRect(x: 0, y: (size.height - Self.lineHeight) / 2,
                                width: size.width, height: Self.lineHeight))
        }
    }
}

// MARK: - The text view

/// `UITextView` configured as selectable, non-editable message text that sizes to its
/// content. Copy writes the readable form of the selection (see `plainText`).
final class MessageTextView: UITextView {
    /// The selected text in readable form, nil with no selection.
    var selectedPlainText: String? {
        guard selectedRange.length > 0, let range = Range(selectedRange, in: text) else { return nil }
        let value = MarkdownAttributedText.plainText(String(text[range]))
        return value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : value
    }

    override func copy(_ sender: Any?) {
        guard let selected = selectedPlainText else { return super.copy(sender) }
        UIPasteboard.general.string = selected
    }
}

/// A coach reply rendered like `MarkdownMessage`, with real range selection.
///
/// Long-press or double-tap selects; the handles extend the selection across the whole
/// reply. The edit menu is the system's (Copy, Select All, Look Up, Translate, Share…) with
/// "Ask about this" added in front, which hands the selected passage to `onAsk`.
struct SelectableMarkdownText: View {
    let markdown: String
    var color: Color = Theme.textPrimary
    /// The title of the custom edit-menu action.
    var askTitle: String = "Ask about this"
    /// Called with the selected passage when the user picks the custom action.
    var onAsk: (String) -> Void = { _ in }
    /// Called for a single tap that is not on a link and does not dismiss a selection.
    var onTap: () -> Void = {}

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let sizeCategory = UIContentSizeCategory(dynamicTypeSize)
        MessageTextRepresentable(markdown: markdown, color: color, sizeCategory: sizeCategory,
                                 askTitle: askTitle, onAsk: onAsk, onTap: onTap)
            .padding(.bottom, -MarkdownAttributedText.trailingLeading(sizeCategory))
    }
}

/// The `UITextView` behind `SelectableMarkdownText`.
private struct MessageTextRepresentable: UIViewRepresentable {
    let markdown: String
    let color: Color
    let sizeCategory: UIContentSizeCategory
    let askTitle: String
    let onAsk: (String) -> Void
    let onTap: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> MessageTextView {
        let view = MessageTextView()
        view.isEditable = false
        view.isSelectable = true
        view.isScrollEnabled = false
        view.backgroundColor = .clear
        view.textContainerInset = .zero
        view.textContainer.lineFragmentPadding = 0
        view.adjustsFontForContentSizeCategory = false   // rebuilt from the environment instead
        view.dataDetectorTypes = []
        view.delegate = context.coordinator
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        view.setContentHuggingPriority(.required, for: .vertical)
        // VoiceOver reads the bubble as one element with its own actions (see MessageRow).
        view.isAccessibilityElement = false

        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.tapped))
        tap.delegate = context.coordinator
        tap.cancelsTouchesInView = false
        // A double tap selects a word; it should not also count as a tap on the bubble.
        for recognizer in view.gestureRecognizers ?? [] {
            if let other = recognizer as? UITapGestureRecognizer, other.numberOfTapsRequired > 1 {
                tap.require(toFail: other)
            }
        }
        view.addGestureRecognizer(tap)
        context.coordinator.textView = view
        return view
    }

    func updateUIView(_ view: MessageTextView, context: Context) {
        let coordinator = context.coordinator
        coordinator.onAsk = onAsk
        coordinator.onTap = onTap
        coordinator.askTitle = askTitle

        let style = MarkdownAttributedText.Style.current(text: color, sizeCategory: sizeCategory)
        // Setting the text again clears a selection, so it is only done when it changed.
        guard coordinator.rendered?.markdown != markdown || coordinator.rendered?.style != style else { return }
        coordinator.rendered = (markdown, style)
        view.attributedText = MarkdownAttributedText.build(markdown, style: style)
        view.linkTextAttributes = [.foregroundColor: style.accent]
        view.tintColor = style.accent
        view.invalidateIntrinsicContentSize()
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: MessageTextView, context: Context) -> CGSize? {
        // With no width proposed SwiftUI is asking how wide the text would like to be.
        let width = proposal.width.map { $0.isFinite ? $0 : 10_000 } ?? 10_000
        guard width >= 1 else { return CGSize(width: 0, height: uiView.font?.lineHeight ?? 20) }
        let fitted = uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        return CGSize(width: min(width, ceil(fitted.width)),
                      height: MarkdownAttributedText.pixelCeil(fitted.height, scale: uiView.traitCollection.displayScale))
    }

    final class Coordinator: NSObject, UITextViewDelegate, UIGestureRecognizerDelegate {
        weak var textView: MessageTextView?
        var rendered: (markdown: String, style: MarkdownAttributedText.Style)?
        var onAsk: (String) -> Void = { _ in }
        var onTap: () -> Void = {}
        var askTitle = "Ask about this"

        // The system edit menu, with the custom action in front of Copy.
        func textView(_ textView: UITextView, editMenuForTextIn range: NSRange,
                      suggestedActions: [UIMenuElement]) -> UIMenu? {
            guard range.length > 0, let view = textView as? MessageTextView,
                  let selected = view.selectedPlainText else { return nil }
            let ask = UIAction(title: askTitle, image: UIImage(systemName: "sparkles")) { [weak self, weak view] _ in
                view?.selectedTextRange = nil
                self?.onAsk(selected)
            }
            return UIMenu(children: [ask] + suggestedActions)
        }

        @objc func tapped() { onTap() }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            guard let view = textView else { return false }
            // A tap that dismisses a selection, or opens a link, is not a tap on the bubble.
            if view.selectedRange.length > 0 { return false }
            let point = touch.location(in: view)
            if let range = view.characterRange(at: point) {
                let index = view.offset(from: view.beginningOfDocument, to: range.start)
                if index >= 0, index < view.attributedText.length,
                   view.attributedText.attribute(.link, at: index, effectiveRange: nil) != nil {
                    return false
                }
            }
            return true
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            true
        }
    }
}

extension UIContentSizeCategory {
    /// SwiftUI's Dynamic Type size as the UIKit category `preferredFont` understands.
    init(_ size: DynamicTypeSize) {
        switch size {
        case .xSmall: self = .extraSmall
        case .small: self = .small
        case .medium: self = .medium
        case .large: self = .large
        case .xLarge: self = .extraLarge
        case .xxLarge: self = .extraExtraLarge
        case .xxxLarge: self = .extraExtraExtraLarge
        case .accessibility1: self = .accessibilityMedium
        case .accessibility2: self = .accessibilityLarge
        case .accessibility3: self = .accessibilityExtraLarge
        case .accessibility4: self = .accessibilityExtraExtraLarge
        case .accessibility5: self = .accessibilityExtraExtraExtraLarge
        @unknown default: self = .large
        }
    }
}
