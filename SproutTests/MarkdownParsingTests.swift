import XCTest
@testable import Sprout

/// Pins `MarkdownMessage`'s block parser — the part that turns Vita's reply text into headings,
/// bullets, numbered items, and thematic rules instead of leaking literal `##` / `- ` / `---`.
/// Focuses on the ambiguous cases a naive line splitter gets wrong: a decimal that looks like a
/// list number, a hashtag that looks like a heading, and emphasis that looks like a bullet or rule.
final class MarkdownParsingTests: XCTestCase {

    func testBulletsDetected() {
        XCTAssertEqual(MarkdownMessage.debugParse("- apple\n- pear"), ["b:0:apple", "b:0:pear"])
    }

    func testAsteriskAndPlusBullets() {
        XCTAssertEqual(MarkdownMessage.debugParse("* a\n+ b"), ["b:0:a", "b:0:b"])
    }

    func testHeadingRequiresTrailingSpace() {
        XCTAssertEqual(MarkdownMessage.debugParse("## Today"), ["h:Today"])
        // A hashtag is prose, NOT a heading (no space after the #).
        XCTAssertEqual(MarkdownMessage.debugParse("#streak day"), ["p:#streak day"])
    }

    func testHorizontalRules() {
        XCTAssertEqual(MarkdownMessage.debugParse("---"), ["rule"])
        XCTAssertEqual(MarkdownMessage.debugParse("***"), ["rule"])
        XCTAssertEqual(MarkdownMessage.debugParse("___"), ["rule"])
    }

    func testEmphasisIsNeverARuleOrBullet() {
        // "**bold**" must stay a paragraph — not mistaken for a rule (all-*) or a bullet (leading *).
        XCTAssertEqual(MarkdownMessage.debugParse("**bold**"), ["p:**bold**"])
    }

    func testNumberedList() {
        XCTAssertEqual(MarkdownMessage.debugParse("1. first\n2. second"),
                       ["n:0:1:first", "n:0:2:second"])
        XCTAssertEqual(MarkdownMessage.debugParse("1) paren"), ["n:0:1:paren"])
    }

    func testDecimalIsNotANumberedItem() {
        // "1.5 cups" is prose: the dot isn't followed by a space, so it's not a list marker.
        XCTAssertEqual(MarkdownMessage.debugParse("1.5 cups of rice"), ["p:1.5 cups of rice"])
    }

    func testIndentedBulletGetsIndentLevel() {
        XCTAssertEqual(MarkdownMessage.debugParse("  - sub"), ["b:1:sub"])
    }

    func testBlankLineSplitsParagraphs() {
        XCTAssertEqual(MarkdownMessage.debugParse("one\n\ntwo"), ["p:one", "p:two"])
    }

    func testConsecutivePlainLinesFoldIntoOneParagraph() {
        XCTAssertEqual(MarkdownMessage.debugParse("line a\nline b"), ["p:line a\nline b"])
    }

    func testEmptyAndWhitespaceOnly() {
        XCTAssertEqual(MarkdownMessage.debugParse(""), [])
        XCTAssertEqual(MarkdownMessage.debugParse("   "), [])
    }

    /// A realistic Vita reply exercising every block type in order.
    func testMixedDocument() {
        let md = """
        Here's today, **Sam**

        ## Macros
        - Protein 78g
        - Carbs 120g

        1. Yogurt
        2. Walk
        ---
        Keep going!
        """
        XCTAssertEqual(MarkdownMessage.debugParse(md), [
            "p:Here's today, **Sam**",
            "h:Macros",
            "b:0:Protein 78g",
            "b:0:Carbs 120g",
            "n:0:1:Yogurt",
            "n:0:2:Walk",
            "rule",
            "p:Keep going!",
        ])
    }
}
