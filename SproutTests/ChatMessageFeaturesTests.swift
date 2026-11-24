import XCTest
import SwiftUI
import UIKit
@testable import Sprout

/// The message features of the chat that are logic rather than layout: the quoted passage
/// ("Ask about this"), the attributed text a selectable reply is laid out from, what a copy
/// of a selection reads as, and the DEBUG long-conversation seed the measurements use.
@MainActor
final class ChatMessageFeaturesTests: XCTestCase {

    // MARK: - ChatQuote

    func testAQuoteAndAQuestionBecomeOneMessage() {
        XCTAssertEqual(ChatQuote.compose(quote: "Protein at each meal keeps you full.", question: " why? "),
                       "> Protein at each meal keeps you full.\n\nwhy?")
        XCTAssertEqual(ChatQuote.compose(quote: "line one\nline two", question: "explain"),
                       "> line one\n> line two\n\nexplain")
        XCTAssertEqual(ChatQuote.compose(quote: nil, question: " just a question "), "just a question")
        XCTAssertEqual(ChatQuote.compose(quote: "   \n ", question: "q"), "q", "a blank selection is no quote")
        XCTAssertEqual(ChatQuote.compose(quote: "the passage", question: "  "),
                       "> the passage\n\n" + ChatQuote.defaultQuestion,
                       "a quote sent with no question asks the default one")
    }

    func testSplitIsTheInverseOfCompose() {
        for (quote, question) in [("one line", "why?"), ("two\nlines", "and this?\nsecond line"),
                                  ("- a list item\n- another", "what about these")] {
            let parts = ChatQuote.split(ChatQuote.compose(quote: quote, question: question))
            XCTAssertEqual(parts.quote, quote)
            XCTAssertEqual(parts.body, question)
        }
    }

    func testOnlyAMessageThatOpensWithAQuoteIsSplit() {
        XCTAssertNil(ChatQuote.split("plain message").quote)
        XCTAssertEqual(ChatQuote.split("plain message").body, "plain message")
        XCTAssertNil(ChatQuote.split("text first\n> then a quote\n\nmore").quote, "a quote further down is just text")
        XCTAssertNil(ChatQuote.split("> a quote and nothing else").quote)
        XCTAssertNil(ChatQuote.split("> quote\nno blank line").quote)
        XCTAssertNil(ChatQuote.split("> quote\n\n   ").quote, "a quote needs a question after it")
        XCTAssertEqual(ChatQuote.split("").body, "")
        let windows = ChatQuote.split("> quoted\r\n\r\nquestion")
        XCTAssertEqual(windows.quote, "quoted")
        XCTAssertEqual(windows.body, "question")
        XCTAssertEqual(ChatQuote.split(">no space\n\nq").quote, "no space")
    }

    func testALongSelectionIsCutAtAWordAndMarked() {
        let long = Array(repeating: "wordy", count: 300).joined(separator: " ")
        let quote = ChatQuote.normalized(long)
        XCTAssertLessThanOrEqual(quote.count, ChatQuote.maxLength + 1)
        XCTAssertTrue(quote.hasSuffix("wordy…"), "cut between words, with an ellipsis")
        XCTAssertEqual(ChatQuote.normalized("  short  \n\n\n  passage "), "short\npassage",
                       "trimmed, blank lines dropped")
        let unbroken = String(repeating: "x", count: 900)
        XCTAssertEqual(ChatQuote.normalized(unbroken).count, ChatQuote.maxLength + 1, "no space to cut at: a hard cut")
        XCTAssertEqual(ChatQuote.normalized(String(repeating: "y", count: ChatQuote.maxLength)).count, ChatQuote.maxLength,
                       "exactly at the limit is left alone")
    }

    func testTheBusCarriesAQuoteAndIgnoresABlankOne() {
        let center = AskVitaCenter()
        center.quote("   ")
        XCTAssertNil(center.pendingQuote)
        center.quote("  a passage \n")
        XCTAssertEqual(center.pendingQuote, "a passage")
        XCTAssertNil(center.pendingTopic, "a quote is not a topic: nothing is sent on the user's behalf")
    }

    // MARK: - Attributed text for a selectable reply

    private var style: MarkdownAttributedText.Style {
        MarkdownAttributedText.Style(text: .white, accent: .green, rule: .gray, sizeCategory: .large)
    }

    private let sample = """
    ## Plan
    Eat **well** and *rest*.
    Second line of the paragraph.

    - Protein at each meal
      - nested item
    1. First step
    ---
    Done with `code` and a [link](https://example.com).
    """

    func testTheStringReadsLikeTheMessageNotLikeMarkdown() {
        let text = MarkdownAttributedText.build(sample, style: style).string
        XCTAssertFalse(text.contains("**"))
        XCTAssertFalse(text.contains("##"))
        XCTAssertFalse(text.contains("---"))
        XCTAssertFalse(text.contains("]("))
        XCTAssertTrue(text.hasPrefix("Plan\n"))
        XCTAssertTrue(text.contains("Eat well and rest.\u{2028}Second line of the paragraph."),
                      "a soft break stays inside its paragraph")
        XCTAssertTrue(text.contains("•\tProtein at each meal"))
        XCTAssertTrue(text.contains("1.\tFirst step"))
        XCTAssertTrue(text.contains("\u{FFFC}"), "the rule is an attachment")
        XCTAssertFalse(text.hasSuffix("\n"), "no trailing paragraph break (it would add a blank line)")
    }

    func testInlineStylesBecomeFontsAndLinks() {
        let attributed = MarkdownAttributedText.build(sample, style: style)
        let text = attributed.string as NSString
        func font(at word: String) -> UIFont? {
            let range = text.range(of: word)
            guard range.location != NSNotFound else { return nil }
            return attributed.attribute(.font, at: range.location, effectiveRange: nil) as? UIFont
        }
        XCTAssertTrue(font(at: "well")?.fontDescriptor.symbolicTraits.contains(.traitBold) ?? false)
        XCTAssertTrue(font(at: "rest")?.fontDescriptor.symbolicTraits.contains(.traitItalic) ?? false)
        XCTAssertFalse(font(at: "Eat")?.fontDescriptor.symbolicTraits.contains(.traitBold) ?? true)
        XCTAssertTrue(font(at: "code")?.fontDescriptor.symbolicTraits.contains(.traitMonoSpace) ?? false)
        XCTAssertEqual(font(at: "Plan")?.pointSize, style.headline.pointSize)
        XCTAssertTrue(font(at: "Plan")?.fontDescriptor.symbolicTraits.contains(.traitBold) ?? false, "headline weight")

        let link = text.range(of: "link")
        XCTAssertEqual(attributed.attribute(.link, at: link.location, effectiveRange: nil) as? URL,
                       URL(string: "https://example.com"))
        let bullet = text.range(of: "•")
        XCTAssertEqual(attributed.attribute(.foregroundColor, at: bullet.location, effectiveRange: nil) as? UIColor, .green,
                       "list markers take the accent colour")
        XCTAssertEqual(attributed.attribute(.foregroundColor, at: text.range(of: "Eat").location, effectiveRange: nil) as? UIColor,
                       .white)
    }

    func testListItemsHangAndNestedItemsIndent() {
        let attributed = MarkdownAttributedText.build(sample, style: style)
        let text = attributed.string as NSString
        func paragraph(at word: String) -> NSParagraphStyle? {
            attributed.attribute(.paragraphStyle, at: text.range(of: word).location, effectiveRange: nil) as? NSParagraphStyle
        }
        let top = try? XCTUnwrap(paragraph(at: "Protein"))
        let nested = try? XCTUnwrap(paragraph(at: "nested"))
        XCTAssertEqual(top?.firstLineHeadIndent, 0)
        XCTAssertGreaterThan(top?.headIndent ?? 0, 8, "wrapped lines line up with the text, not the marker")
        XCTAssertEqual(nested?.firstLineHeadIndent, MarkdownAttributedText.indentStep)
        XCTAssertEqual((nested?.headIndent ?? 0) - (top?.headIndent ?? 0), MarkdownAttributedText.indentStep)
        XCTAssertEqual(paragraph(at: "Eat")?.paragraphSpacing ?? 0,
                       MarkdownAttributedText.blockSpacing - style.body.leading, accuracy: 0.001,
                       "the gap between blocks, less the leading TextKit already put under the line")
        XCTAssertEqual(paragraph(at: "Done")?.paragraphSpacing, 0, "nothing after the last block")
    }

    func testTextSizeFollowsDynamicType() {
        var large = style
        large.sizeCategory = .accessibilityExtraExtraExtraLarge
        let normal = MarkdownAttributedText.build("hello", style: style)
        let big = MarkdownAttributedText.build("hello", style: large)
        let normalFont = normal.attribute(.font, at: 0, effectiveRange: nil) as? UIFont
        let bigFont = big.attribute(.font, at: 0, effectiveRange: nil) as? UIFont
        XCTAssertEqual(normalFont?.pointSize, 17)
        XCTAssertGreaterThan(bigFont?.pointSize ?? 0, 40)
        XCTAssertEqual(UIContentSizeCategory(DynamicTypeSize.large), .large)
        XCTAssertEqual(UIContentSizeCategory(DynamicTypeSize.accessibility5), .accessibilityExtraExtraExtraLarge)
        XCTAssertEqual(UIContentSizeCategory(DynamicTypeSize.xSmall), .extraSmall)
    }

    func testEmptyAndPlainMessages() {
        XCTAssertEqual(MarkdownAttributedText.build("", style: style).length, 0)
        XCTAssertEqual(MarkdownAttributedText.build("just text", style: style).string, "just text")
        XCTAssertEqual(MarkdownAttributedText.build("one\n\ntwo", style: style).string, "one\ntwo",
                       "two paragraphs are two paragraphs; the gap is spacing, not a blank line")
    }

    func testWhatACopiedSelectionReadsAs() {
        let built = MarkdownAttributedText.build(sample, style: style).string
        let copied = MarkdownAttributedText.plainText(built)
        XCTAssertFalse(copied.contains("\u{2028}"))
        XCTAssertFalse(copied.contains("\t"))
        XCTAssertFalse(copied.contains("\u{FFFC}"))
        XCTAssertTrue(copied.contains("Eat well and rest.\nSecond line of the paragraph."))
        XCTAssertTrue(copied.contains("• Protein at each meal"))
        XCTAssertTrue(copied.contains("1. First step\n---\nDone with code and a link."))
    }

    func testTheTextViewCopiesAndQuotesTheSelectedRangeOnly() {
        let view = MessageTextView()
        view.attributedText = MarkdownAttributedText.build("First sentence. Second sentence.\n\n- item", style: style)
        XCTAssertNil(view.selectedPlainText, "nothing selected")

        view.selectedRange = (view.text as NSString).range(of: "Second sentence.")
        XCTAssertEqual(view.selectedPlainText, "Second sentence.")
        UIPasteboard.general.string = "before"
        view.copy(nil)
        XCTAssertEqual(UIPasteboard.general.string, "Second sentence.")

        view.selectedRange = NSRange(location: 0, length: (view.text as NSString).length)
        XCTAssertEqual(view.selectedPlainText, "First sentence. Second sentence.\n• item",
                       "a selection across blocks reads as plain text")
    }

    func testTheSelectableReplyIsAsTallAsTheSwiftUIOneItReplaces() {
        // A reply types itself out as SwiftUI text and then settles into the text view. If
        // the two measured differently the bubble would jump at that moment.
        let samples = [
            "Short reply.",
            "A longer reply that wraps onto several lines in a bubble of ordinary width, so line height matters as much as paragraph spacing does.",
            "First paragraph.\n\nSecond paragraph, which is long enough to wrap around at least once in the bubble.",
            "## Heading\nBody under the heading.\n\n- one\n- two, long enough to wrap around to a second line under the bullet\n\n1. first\n2. second",
            "Before\n\n---\n\nAfter",
        ]
        let width: CGFloat = 268
        for markdown in samples {
            let host = UIHostingController(rootView: MarkdownMessage(markdown).frame(width: width, alignment: .leading))
            let swiftUI = host.sizeThatFits(in: CGSize(width: width, height: .greatestFiniteMagnitude)).height

            let view = replyTextView(markdown)
            let fitted = view.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
            // What `SelectableMarkdownText` occupies: the text view, less the leading under its last line.
            let uiKit = MarkdownAttributedText.pixelCeil(fitted.height, scale: 3)
                - MarkdownAttributedText.trailingLeading(.large)

            XCTAssertEqual(uiKit, swiftUI, accuracy: 1.5, "heights differ for: \(markdown.prefix(30))…")
        }
    }

    /// A text view set up the way `SelectableMarkdownText` sets its own up.
    private func replyTextView(_ markdown: String) -> MessageTextView {
        let view = MessageTextView()
        view.isScrollEnabled = false
        view.textContainer.lineFragmentPadding = 0
        view.textContainerInset = .zero
        view.attributedText = MarkdownAttributedText.build(markdown, style: style)
        return view
    }

    func testEveryLineIsDrawnAtTheSizeTheViewReports() throws {
        // A text view that cannot scroll draws only the lines that fit its text container.
        // An earlier version shortened the view by the font's leading and lost the last
        // line of every reply whose last line wrapped.
        let reply = "That's a good question. Short answer: **yes**, and here is why.\n\n"
            + "- Your trend is what counts, not one reading.\n- Protein at each meal keeps you full.\n\n"
            + "Want me to look at this week with you?"
        for width in stride(from: CGFloat(180), through: 330, by: 7) {
            let view = replyTextView(reply)
            let fitted = view.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
            let size = CGSize(width: min(width, ceil(fitted.width)),
                              height: MarkdownAttributedText.pixelCeil(fitted.height, scale: 3))
            view.frame = CGRect(origin: .zero, size: size)
            view.layoutIfNeeded()

            let manager = try XCTUnwrap(view.textLayoutManager, "TextKit 2")
            manager.ensureLayout(for: manager.documentRange)
            var lastLaidOut: (any NSTextLocation)?
            var lowestLine: CGFloat = 0
            manager.enumerateTextLayoutFragments(from: manager.documentRange.location,
                                                 options: [.ensuresLayout]) { fragment in
                lastLaidOut = fragment.rangeInElement.endLocation
                lowestLine = max(lowestLine, fragment.layoutFragmentFrame.maxY)
                return true
            }
            let end = try XCTUnwrap(lastLaidOut)
            XCTAssertEqual(manager.offset(from: end, to: manager.documentRange.endLocation), 0,
                           "width \(width): the last paragraph was not laid out")
            XCTAssertLessThanOrEqual(lowestLine, view.textContainer.size.height + 0.5,
                                     "width \(width): the last line does not fit the text container")
        }
    }

    // MARK: - The DEBUG long-conversation seed

    #if DEBUG
    func testTheLongConversationSeedIsDeterministicOrderedAndEndsOnAReply() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        for count in [1, 2, 3, 200, 201, 1_000] {
            let chat = ChatDebug.longChat(count: count, coachName: "Vita", userName: "Alex", now: now)
            XCTAssertEqual(chat.count, count)
            XCTAssertEqual(chat, ChatDebug.longChat(count: count, coachName: "Vita", userName: "Alex", now: now))
            XCTAssertTrue(chat[0].isSystemSeed)
            XCTAssertEqual(chat.filter(\.isSystemSeed).count, 1)
            XCTAssertEqual(chat.last?.role, "assistant", "\(count): the conversation ends on a reply")
            XCTAssertEqual(Set(chat.map(\.createdAt)).count, count, "every timestamp is distinct")
            XCTAssertEqual(chat.map(\.createdAt), chat.map(\.createdAt).sorted())
            XCTAssertEqual(chat.last?.createdAt, now.addingTimeInterval(-120))
            if count > 2 {
                for index in 2..<count { XCTAssertNotEqual(chat[index].role, chat[index - 1].role, "\(count) at \(index)") }
            }
        }
        XCTAssertTrue(ChatDebug.longChat(count: 0, coachName: "Vita", userName: "Alex", now: now).isEmpty)
        XCTAssertEqual(ChatDebug.value(after: "--demo-long-chat", in: ["app", "--demo-long-chat", "500"]), "500")
        XCTAssertNil(ChatDebug.value(after: "--demo-long-chat", in: ["app", "--demo-long-chat"]))
    }
    #endif
}
