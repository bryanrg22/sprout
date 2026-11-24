import XCTest
import SwiftUI
import UIKit
@testable import Victoria

/// Text in both looks meets WCAG 2.x's 4.5:1 minimum for normal text against the surfaces it
/// is drawn on (EVAL_REPORT 29). Computed from the theme's own colors with WCAG's relative
/// luminance formula, so a later color change cannot quietly drop below it.
final class ThemeContrastTests: XCTestCase {

    private func luminance(_ color: Color) -> Double {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(color).getRed(&r, green: &g, blue: &b, alpha: &a)
        func linear(_ c: CGFloat) -> Double {
            let v = Double(c)
            return v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(r) + 0.7152 * linear(g) + 0.0722 * linear(b)
    }

    private func ratio(_ a: Color, _ b: Color) -> Double {
        let (la, lb) = (luminance(a), luminance(b))
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }

    func testTheFormulaMatchesKnownValues() {
        XCTAssertEqual(ratio(.black, .white), 21, accuracy: 0.01)
        XCTAssertEqual(ratio(.white, .white), 1, accuracy: 0.01)
        XCTAssertEqual(ratio(Color(hex: 0x767676), .white), 4.54, accuracy: 0.02, "the classic AA grey")
    }

    func testBodyTextMeetsTheMinimumOnEverySurfaceInBothLooks() {
        for (name, skin) in [("cool", ThemeSkin.cool), ("cute", ThemeSkin.cute)] {
            for (surfaceName, surface) in [("background", skin.background), ("card", skin.card), ("raised card", skin.cardRaised)] {
                XCTAssertGreaterThanOrEqual(ratio(skin.textPrimary, surface), 4.5, "\(name): primary text on \(surfaceName)")
                XCTAssertGreaterThanOrEqual(ratio(skin.textSecondary, surface), 4.5, "\(name): secondary text on \(surfaceName)")
            }
        }
    }

    func testTheLightLooksSecondaryTextIsTheMeasuredValue() {
        XCTAssertEqual(ratio(ThemeSkin.cute.textSecondary, ThemeSkin.cute.card), 5.2, accuracy: 0.05)
        XCTAssertEqual(ratio(ThemeSkin.cute.textSecondary, ThemeSkin.cute.background), 4.75, accuracy: 0.05)
    }
}
