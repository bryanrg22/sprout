import Foundation
@testable import Victoria

/// Pure scoring functions. Each is unit-tested in `GraderTests` against hand-written
/// outputs, because a wrong grader silently corrupts every number it produces.
enum Graders {

    // MARK: - Meal estimate against a known total

    struct MealTruth: Decodable, Sendable {
        let id: String
        let description: String
        let kcal: Double
        let protein_g: Double
        let carbs_g: Double
        let fat_g: Double
        let source: String
    }

    /// The calorie tolerance a case passes within. 20% is the tolerance US food
    /// labelling allows a declared calorie value (21 CFR 101.9(g)(5)).
    static let mealCalorieTolerance = 0.20

    static func absPctError(_ got: Double, _ want: Double) -> Double {
        guard want != 0 else { return got == 0 ? 0 : 1 }
        return abs(got - want) / abs(want)
    }

    static func meal(_ estimate: FoodPhotoAnalyzer.Estimate, truth: MealTruth) -> (scores: [String: Double], pass: Bool) {
        let kcalError = absPctError(estimate.total_calories, truth.kcal)
        let itemSum = estimate.items.reduce(0) { $0 + $1.calories }
        // Macro error is measured in grams: a percentage is meaningless on a 0 g truth.
        var scores: [String: Double] = [
            "kcal_pct_error": kcalError,
            "kcal_within_20pct": kcalError <= mealCalorieTolerance ? 1 : 0,
            "protein_abs_error_g": abs(estimate.total_protein_g - truth.protein_g),
            "carbs_abs_error_g": abs(estimate.total_carbs_g - truth.carbs_g),
            "fat_abs_error_g": abs(estimate.total_fat_g - truth.fat_g),
            // The model's own range should contain the truth when it is honest about uncertainty.
            "truth_in_stated_range": (estimate.calories_low...max(estimate.calories_low, estimate.calories_high))
                .contains(truth.kcal) ? 1 : 0,
            // The total must be the sum of its items (within 5%), or the UI shows numbers that disagree.
            "items_sum_to_total": absPctError(itemSum, estimate.total_calories) <= 0.05 ? 1 : 0,
            // Low must not exceed high, and the total must sit inside the range.
            "range_well_formed": (estimate.calories_low <= estimate.total_calories
                                  && estimate.total_calories <= estimate.calories_high) ? 1 : 0,
        ]
        scores["confidence_is_valid"] = EstimateConfidence(rawValue: estimate.confidence) == nil ? 0 : 1
        return (scores, kcalError <= mealCalorieTolerance)
    }

    // MARK: - Numbers a rewording must keep

    /// Every number in the text, normalized ("8,400" → 8400, "7.5" → 7.5), including
    /// numbers written as words from two to ninety-nine ("fourteen days" → 14,
    /// "twenty-eight" → 28). "One" is deliberately not counted: in running prose it is
    /// far more often a pronoun or a determiner ("one day at a time") than a quantity.
    static func numbers(in text: String) -> [Double] {
        let pattern = #"\d[\d,]*(?:\.\d+)?"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        let digits: [Double] = regex.matches(in: text, range: range).compactMap { match in
            guard let r = Range(match.range, in: text) else { return nil }
            var token = String(text[r]).replacingOccurrences(of: ",", with: "")
            if token.hasSuffix(".") { token.removeLast() }
            return Double(token)
        }
        return digits + numberWords(in: text)
    }

    private static let unitWords: [String: Double] = [
        "two": 2, "three": 3, "four": 4, "five": 5, "six": 6, "seven": 7, "eight": 8, "nine": 9,
        "ten": 10, "eleven": 11, "twelve": 12, "thirteen": 13, "fourteen": 14, "fifteen": 15,
        "sixteen": 16, "seventeen": 17, "eighteen": 18, "nineteen": 19,
    ]
    private static let tensWords: [String: Double] = [
        "twenty": 20, "thirty": 30, "forty": 40, "fifty": 50, "sixty": 60, "seventy": 70,
        "eighty": 80, "ninety": 90,
    ]
    private static let onesAfterTens: [String: Double] = [
        "one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6, "seven": 7, "eight": 8, "nine": 9,
    ]

    static func numberWords(in text: String) -> [Double] {
        // Words, keeping the hyphen inside "twenty-eight" and "ten-minute" as a separator.
        let words = text.lowercased().split { !$0.isLetter }.map(String.init)
        var out: [Double] = []
        var index = 0
        while index < words.count {
            let word = words[index]
            if let tens = tensWords[word] {
                if index + 1 < words.count, let ones = onesAfterTens[words[index + 1]] {
                    out.append(tens + ones); index += 2; continue
                }
                out.append(tens)
            } else if let value = unitWords[word] {
                out.append(value)
            }
            index += 1
        }
        return out
    }

    /// A rewording keeps the numbers when it states every number of the source and
    /// states no number the source did not have.
    static func numbersPreserved(source: String, rewrite: String) -> (allKept: Bool, noneInvented: Bool) {
        let want = Set(numbers(in: source)), got = Set(numbers(in: rewrite))
        return (want.isSubset(of: got), got.isSubset(of: want))
    }

    static func sentenceCount(_ text: String) -> Int {
        var count = 0
        text.enumerateSubstrings(in: text.startIndex..., options: .bySentences) { sentence, _, _, _ in
            if let sentence, !sentence.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { count += 1 }
        }
        return count
    }

    /// Third-person feminine words about the reader. The brief addresses the reader as
    /// "you"; any of these in a note for a user who is not a woman is a wrong-person error.
    static func containsFemininePronoun(_ text: String) -> Bool {
        let words = text.lowercased().split { !$0.isLetter }.map(String.init)
        return words.contains { ["she", "her", "hers", "herself"].contains($0) }
    }

    // MARK: - The action a coach tool call resolves to

    /// A tool call as the app understands it after `CoachTools.parse`: the action's case
    /// name, the first number it carries, and its full description for substring checks.
    struct ActionView: Equatable {
        let kind: String
        let text: String

        init(_ action: CoachTools.ParsedRequest.Action) {
            let described = String(describing: action)
            kind = described.split(separator: "(", maxSplits: 1).first.map(String.init) ?? described
            text = described
        }

        init(kind: String, text: String) { self.kind = kind; self.text = text }

        /// The number following `key:` in the description, or the first number in it.
        /// `a*b` multiplies the two (a food's calories are per serving, times `quantity`).
        func number(key: String? = nil) -> Double? {
            let body = text.dropFirst(kind.count)
            guard let key else { return Graders.signedNumbers(in: String(body)).first }
            var product = 1.0
            for part in key.split(separator: "*") {
                guard let range = body.range(of: "\(part): "),
                      let value = Graders.signedNumbers(in: String(body[range.upperBound...])).first else { return nil }
                product *= value
            }
            return product
        }
    }

    static func signedNumbers(in text: String) -> [Double] {
        guard let regex = try? NSRegularExpression(pattern: #"-?\d+(?:\.\d+)?"#) else { return [] }
        return regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap {
            Range($0.range, in: text).flatMap { Double(text[$0]) }
        }
    }

    struct ToolExpectation: Decodable, Sendable {
        let id: String
        /// Which fixture user says it: `gain` or `loss`.
        let profile: String
        let utterance: String
        /// Acceptable action kinds; `none` means the right move is to answer in prose.
        let kinds: [String]
        /// The number the action must carry (in the app's stored unit), if it has one.
        let value: Double?
        let tolerance: Double?
        /// Read the number after this label instead of the first one (e.g. `calories`).
        let valueKey: String?
        /// Lower-cased substrings the action description must contain.
        let contains: [String]?
        let why: String
    }

    /// `called`: the tool the model asked for, already parsed by the app, or nil for prose.
    /// `invalid`: the model called a tool the app rejected (unknown tool or bad arguments).
    static func toolChoice(expect: ToolExpectation, called: ActionView?, invalid: Bool)
        -> (scores: [String: Double], pass: Bool) {
        let wantsNone = expect.kinds == ["none"]
        let acceptsNone = expect.kinds.contains("none")
        let decisionRight: Bool = {
            if invalid { return !wantsNone }          // it did decide to act
            if called == nil { return acceptsNone }
            return !wantsNone
        }()
        let kindRight: Bool = {
            if invalid { return false }
            guard let called else { return acceptsNone }
            return expect.kinds.contains(called.kind)
        }()
        var argumentsRight = kindRight
        if kindRight, let called {
            if let want = expect.value {
                let got = called.number(key: expect.valueKey)
                argumentsRight = got.map { abs($0 - want) <= (expect.tolerance ?? 0.0001) } ?? false
            }
            if argumentsRight, let needles = expect.contains {
                let haystack = called.text.lowercased()
                argumentsRight = needles.allSatisfy { haystack.contains($0.lowercased()) }
            }
        }
        let scores: [String: Double] = [
            "decision_correct": decisionRight ? 1 : 0,     // act vs. answer
            "tool_correct": kindRight ? 1 : 0,
            "arguments_correct": argumentsRight ? 1 : 0,
            "call_was_valid": invalid ? 0 : 1,             // the app accepted the call it got
            "acted_when_should_not": (wantsNone && (called != nil || invalid)) ? 1 : 0,
        ]
        return (scores, decisionRight && kindRight && argumentsRight)
    }
}
