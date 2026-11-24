import Foundation
import ImageIO
@testable import Sprout

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

        // The label nutrients the estimator is asked for (`Nutrient.estimable`), from the same
        // USDA records as the macros (`meal_describe/v3` on). `nil` = the record does not list
        // the nutrient for at least one ingredient, so the total is not known and that
        // nutrient is NOT graded for the case. Optional, so a v1 row still decodes. The
        // dataset also carries the label's other seven nutrients (added sugars, trans fat,
        // cholesterol, vitamin D, calcium, iron, potassium); nothing reads them until the
        // estimator is asked for one.
        var fiber_g: Double? = nil
        var sugars_g: Double? = nil
        var saturated_fat_g: Double? = nil
        var sodium_mg: Double? = nil

        /// Nutrients (by `Nutrient.argumentName`, e.g. "sodium_mg") for which the description
        /// gives no basis, so the right answer is "not known". No v3 case has any: every v3
        /// portion is a named food in grams. The field exists so a later version with vague
        /// descriptions can label them.
        var no_basis: [String]? = nil

        func truth(for nutrient: Nutrient) -> Double? {
            switch nutrient {
            case .fiber: return fiber_g
            case .sugars: return sugars_g
            case .saturatedFat: return saturated_fat_g
            case .sodium: return sodium_mg
            default: return nil
            }
        }
    }

    /// The estimate's value for one of the estimable nutrients (`nil` = it said not known).
    static func estimated(_ nutrient: Nutrient, in estimate: FoodPhotoAnalyzer.Estimate) -> Double? {
        estimate.detail[nutrient]
    }

    /// Scores for the label nutrients, added to the meal scores. None of them decides the pass.
    ///
    /// For each nutrient the estimator is asked for:
    /// - `<name>_abs_error`: |estimate − truth| in the nutrient's own unit (the key carries
    ///   it: `fiber_g_abs_error`, `sodium_mg_abs_error`). Recorded only when the truth is
    ///   known AND the estimate gave a number, so an abstention never counts as an error of
    ///   zero or of the whole amount.
    /// - `<name>_answered`: 1 when the estimate gave a number, 0 when it said not known.
    ///   Recorded when the truth is known (the model had a basis); its mean is the share of
    ///   answerable cases the model actually answered.
    /// - `<name>_unknown_when_no_basis`: 1 when the estimate said not known, 0 when it gave a
    ///   number anyway. Recorded only for a nutrient the case lists in `no_basis`.
    static func mealDetail(_ estimate: FoodPhotoAnalyzer.Estimate, truth: MealTruth) -> [String: Double] {
        var scores: [String: Double] = [:]
        let noBasis = Set(truth.no_basis ?? [])
        for nutrient in Nutrient.estimable {
            let name = nutrient.argumentName
            let got = estimated(nutrient, in: estimate)
            if noBasis.contains(name) {
                scores["\(name)_unknown_when_no_basis"] = got == nil ? 1 : 0
                continue
            }
            guard let want = truth.truth(for: nutrient) else { continue }   // USDA does not say: not graded
            scores["\(name)_answered"] = got == nil ? 0 : 1
            if let got { scores["\(name)_abs_error"] = abs(got - want) }
        }
        return scores
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
        // The label nutrients are reported beside the macros; the pass rule is unchanged.
        scores.merge(mealDetail(estimate, truth: truth)) { existing, _ in existing }
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

    // MARK: - A generated character image (the `Avatar` evaluation)

    /// What the code can tell about a character image without a person looking at it.
    /// Likeness, and fit with the two existing characters, are the owner's own rating.
    struct ImageMetrics: Equatable {
        var decodable = false
        var width = 0
        var height = 0
        var hasAlpha = false
        /// Every pixel of the two TOP corner blocks is clear (alpha at or under `clearAlphaCeiling`). This is the background check
        /// that decides a pass: the style is a bust cut off by the bottom edge, so shoulders
        /// may rightly reach the bottom corners (the second built-in character's do).
        var transparentTopCorners = false
        /// Every pixel of all four corner blocks is clear. Recorded, not required.
        var transparentCorners = false
        /// Share of pixels with alpha exactly 0.
        var transparentShare = 0.0
        /// Distinct colours among the solid pixels after quantisation (see `distinctColours`).
        var distinctColours = 0

        var isSquare1024: Bool { width == 1024 && height == 1024 }
    }

    /// Side of each corner block checked for transparency, as a share of the image side.
    static let cornerBlockShare = 0.03
    /// A pixel at or under this alpha (about 3%) is graded as clear, and one at or over
    /// `solidAlphaFloor` (about 98%) as solid. Measured on the first live run (EVAL_REPORT
    /// 23): the image models return a character whose solid pixels are at alpha 253 or 254,
    /// never 255, and leave a scatter of alpha 1 and 2 in the cleared background. Neither
    /// can be seen, so neither decides a grade. Exact 0 and exact 255 graded all nine
    /// usable characters of that run as "no colours at all".
    static let clearAlphaCeiling: UInt8 = 8
    static let solidAlphaFloor: UInt8 = 250
    /// Bits kept per channel when counting colours: 4 bits = 16 levels = 4,096 possible colours.
    static let colourBits = 4
    /// A quantised colour counts only if it covers at least this share of the solid pixels,
    /// so a handful of stray anti-aliased pixels do not look like extra palette entries.
    static let minColourShare = 0.002
    /// At or under this many colours the image is taken to be flat-palette pixel art.
    /// Calibrated on 2026-11-23 (EVAL_REPORT 23) on thirteen images: ten pixel characters
    /// (nine generated, one built in) counted 24 to 45, and the three photographs they were
    /// made from counted 72 to 81. The limit is the middle of that gap. Thirteen images is a
    /// small set: a count between 46 and 71 has never been seen and should be looked at.
    static let pixelArtColourLimit = 58

    static func imageMetrics(_ data: Data) -> ImageMetrics {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
              let pixels = AvatarImage.rgba(of: image) else { return ImageMetrics() }
        var metrics = ImageMetrics()
        metrics.decodable = true
        metrics.width = pixels.width
        metrics.height = pixels.height
        metrics.hasAlpha = AvatarImage.hasAlphaChannel(image)
        metrics.transparentShare = pixels.transparentShare
        metrics.transparentTopCorners = cornersAreTransparent(pixels, topOnly: true)
        metrics.transparentCorners = cornersAreTransparent(pixels, topOnly: false)
        metrics.distinctColours = distinctColours(pixels)
        return metrics
    }

    static func cornersAreTransparent(_ pixels: AvatarImage.Pixels, topOnly: Bool) -> Bool {
        let block = max(1, Int((Double(min(pixels.width, pixels.height)) * cornerBlockShare).rounded()))
        guard pixels.width >= block, pixels.height >= block else { return false }
        let xs = [0, pixels.width - block]
        let ys = topOnly ? [0] : [0, pixels.height - block]
        for x0 in xs {
            for y0 in ys {
                for y in y0..<(y0 + block) {
                    for x in x0..<(x0 + block) where pixels.alpha(x: x, y: y) > clearAlphaCeiling { return false }
                }
            }
        }
        return true
    }

    /// Colours among the solid pixels (alpha at or over `solidAlphaFloor`), each channel cut
    /// to `colourBits` bits, counting only colours that cover at least `minColourShare` of them.
    static func distinctColours(_ pixels: AvatarImage.Pixels, bits: Int = colourBits,
                                minShare: Double = minColourShare) -> Int {
        let shift = UInt8(8 - bits)
        var counts: [UInt32: Int] = [:]
        var opaque = 0
        var index = 0
        while index < pixels.bytes.count {
            if pixels.bytes[index + 3] >= solidAlphaFloor {
                opaque += 1
                let r = UInt32(pixels.bytes[index] >> shift)
                let g = UInt32(pixels.bytes[index + 1] >> shift)
                let b = UInt32(pixels.bytes[index + 2] >> shift)
                counts[(r << 16) | (g << 8) | b, default: 0] += 1
            }
            index += 4
        }
        guard opaque > 0 else { return 0 }
        let floor = Double(opaque) * minShare
        return counts.values.filter { Double($0) >= floor }.count
    }

    /// Scores for one generated character. Pass = the app could show it as a character:
    /// a square 1024 PNG whose top corners are clear and whose palette is small.
    static func avatar(_ data: Data) -> (scores: [String: Double], pass: Bool) {
        let m = imageMetrics(data)
        let isPixelArt = m.decodable && m.distinctColours > 0 && m.distinctColours <= pixelArtColourLimit
        let scores: [String: Double] = [
            "decodable": m.decodable ? 1 : 0,
            "square_1024": m.isSquare1024 ? 1 : 0,
            "has_alpha": m.hasAlpha ? 1 : 0,
            "transparent_top_corners": m.transparentTopCorners ? 1 : 0,
            "transparent_corners": m.transparentCorners ? 1 : 0,
            "transparent_share": m.transparentShare,
            "distinct_colours": Double(m.distinctColours),
            "is_pixel_art": isPixelArt ? 1 : 0,
        ]
        return (scores, m.decodable && m.isSquare1024 && m.transparentTopCorners && isPixelArt)
    }

    /// USD per million tokens for an image model.
    struct ImageRates: Equatable {
        var textInput: Double
        var imageInput: Double
        var imageOutput: Double
    }

    /// Read from each model's own page on 2026-11-22
    /// (developers.openai.com/api/docs/models/gpt-image-2.6-flare and -sunburst). The pages
    /// give no per-image price: the cost of an image is its tokens at these rates, which is
    /// why the evaluation records the usage block. A model missing here gets no cost.
    static let imageRates: [String: ImageRates] = [
        "gpt-image-2.6-flare": ImageRates(textInput: 5, imageInput: 8, imageOutput: 30),
        "gpt-image-2.6-sunburst": ImageRates(textInput: 5, imageInput: 8, imageOutput: 30),
    ]

    /// The list-price cost of one image call, or nil for a model with no rates on file.
    /// Input tokens the response does not attribute to text or image are priced as image
    /// input (the dearer of the two), so an incomplete breakdown never understates the cost.
    static func imageCostUSD(model: String, usage: AvatarGenerator.Usage,
                             rates: [String: ImageRates] = imageRates) -> Double? {
        guard let rate = rates[model] else { return nil }
        let unattributed = max(0, usage.inputTokens - usage.inputTextTokens - usage.inputImageTokens)
        let input = Double(usage.inputTextTokens) * rate.textInput
            + Double(usage.inputImageTokens + unattributed) * rate.imageInput
        return (input + Double(usage.outputTokens) * rate.imageOutput) / 1_000_000
    }
}

// MARK: - Text checks shared by the wording graders

extension Graders {

    /// Who a text is addressed to: the name the feature was given, and which third-person
    /// pronouns about the reader would be about someone else.
    struct Reader: Sendable, Equatable {
        let name: String
        let isWoman: Bool
        let isMan: Bool
    }

    /// The masculine counterpart of `containsFemininePronoun`.
    static func containsMasculinePronoun(_ text: String) -> Bool {
        let words = text.lowercased().split { !$0.isLetter }.map(String.init)
        return words.contains { ["he", "him", "his", "himself"].contains($0) }
    }

    /// Every one of these features addresses the reader as "you". A feminine pronoun in a
    /// text for a reader who is not a woman, or a masculine one for a reader who is not a
    /// man, speaks of the reader as somebody else.
    static func wrongPersonPronoun(_ text: String, reader: Reader) -> Bool {
        (!reader.isWoman && containsFemininePronoun(text)) || (!reader.isMan && containsMasculinePronoun(text))
    }

    /// Words in a text: whitespace-separated tokens that hold a letter or a digit, so a
    /// lone emoji or a dash is not a word.
    static func wordCount(_ text: String) -> Int {
        text.split { $0.isWhitespace }.filter { $0.contains { $0.isLetter || $0.isNumber } }.count
    }

    /// Emoji in a text, counted as the reader sees them (a flag or a skin-toned hand is one).
    static func emojiCount(_ text: String) -> Int {
        text.filter { character in
            guard let first = character.unicodeScalars.first else { return false }
            if character.unicodeScalars.contains(where: { $0.properties.isEmojiPresentation }) { return true }
            // A text-style symbol shown as an emoji by a variation selector ("❤️"), or a keycap.
            return character.unicodeScalars.count > 1 && first.properties.isEmoji
        }.count
    }

    /// Whether `phrase` occurs in `text` as whole words, ignoring case: "bad" is found in
    /// "not bad!" and not in "badge"; "should" is found in "shouldn't".
    static func containsPhrase(_ text: String, _ phrase: String) -> Bool {
        matches(text.replacingOccurrences(of: "’", with: "'"),
                #"(?<![\p{L}\p{N}])"# + NSRegularExpression.escapedPattern(for: phrase) + #"(?:n't)?(?![\p{L}\p{N}])"#)
    }

    /// Sentences that hold a letter or a digit. `sentenceCount` counts an emoji standing
    /// after the last full stop as a sentence of its own; these graders must not.
    static func proseSentenceCount(_ text: String) -> Int {
        var count = 0
        text.enumerateSubstrings(in: text.startIndex..., options: .bySentences) { sentence, _, _, _ in
            if let sentence, sentence.contains(where: { $0.isLetter || $0.isNumber }) { count += 1 }
        }
        return count
    }

    /// Whether a word of `text` begins with `stem`, ignoring case: "peanut" is found in
    /// "Peanuts" and "egg" in "eggs", but "egg" is not found in "veggie" nor "rain" in "training".
    static func mentions(_ text: String, _ stem: String) -> Bool {
        matches(text, #"(?<![\p{L}\p{N}])"# + NSRegularExpression.escapedPattern(for: stem))
    }

    private static func matches(_ text: String, _ pattern: String) -> Bool {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return false }
        return regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
    }

    /// Whether `text` names a food, as a whole word in the singular or the plural: "egg" is
    /// found in "egg whites" and "two eggs", and not in "eggplant" or "veggies".
    static func namesFood(_ text: String, _ food: String) -> Bool {
        [food, food + "s", food + "es"].contains { containsPhrase(text, $0) }
    }

    /// The phrases of `list` that `text` contains, as whole words.
    static func phrases(in text: String, from list: [String]) -> [String] {
        list.filter { containsPhrase(text, $0) }
    }

    /// The numbers `text` states that `given` does not (digits, and words from two to ninety-nine).
    static func numbersNotGiven(in text: String, given: String) -> [Double] {
        Set(numbers(in: text)).subtracting(numbers(in: given)).sorted()
    }

    /// A line that begins like a list item or a header.
    static func hasListOrHeader(_ text: String) -> Bool {
        text.split(separator: "\n").contains { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            return ["- ", "* ", "• ", "#"].contains { trimmed.hasPrefix($0) }
        }
    }

    /// `minItems...maxItems` of an array property in one of the app's tool schemas, so a
    /// grader checks the bounds the feature itself declares.
    static func itemBounds(_ schema: [String: Any], _ property: String) -> ClosedRange<Int>? {
        guard let properties = schema["properties"] as? [String: Any],
              let array = properties[property] as? [String: Any],
              let low = array["minItems"] as? Int, let high = array["maxItems"] as? Int, low <= high else { return nil }
        return low...high
    }

    private static func flag(_ condition: Bool) -> Double { condition ? 1 : 0 }
}

// MARK: - insightLine: the one-line rewording of the insight the engine chose

extension Graders {

    /// Grades the line the app would show (`InsightPhraser.rephrase` returned it, so its
    /// sanitiser already passed it: no banned phrase, at most 180 characters).
    ///
    /// PASS = the facts are intact and it is about the right person:
    /// - every number of the template it replaces is still there ("match this meaning"),
    /// - it states no number that neither the template nor the observation gave it
    ///   ("Do NOT add new facts, numbers"),
    /// - no wrong-person pronoun (the line speaks to the reader as "you").
    /// Recorded, not required: one sentence, at most 22 words (the prompt says "max ~22"),
    /// at most one emoji, no hashtag, and whether the wording changed at all.
    static func insightLine(template: String, hint: String, line: String, reader: Reader)
        -> (scores: [String: Double], pass: Bool) {
        let allKept = Set(numbers(in: template)).isSubset(of: Set(numbers(in: line)))
        let noneInvented = numbersNotGiven(in: line, given: template + " " + hint).isEmpty
        let wrongPerson = wrongPersonPronoun(line, reader: reader)
        let scores: [String: Double] = [
            "used": 1,
            "all_numbers_kept": flag(allKept),
            "no_number_invented": flag(noneInvented),
            "wrong_person_pronoun": flag(wrongPerson),
            "one_sentence": flag(proseSentenceCount(line) <= 1),
            "at_most_22_words": flag(wordCount(line) <= 22),
            "at_most_one_emoji": flag(emojiCount(line) <= 1),
            "no_hashtag": flag(!line.contains("#")),
            "changed_the_wording": flag(line != template),
        ]
        return (scores, allKept && noneInvented && !wrongPerson)
    }
}

// MARK: - weeklyReflection: the weekly note

extension Graders {

    /// Grades the note the app would show (`WeeklyReflection.written` returned it, so its
    /// sanitiser already passed it: no banned phrase, no digit, at most 900 characters).
    /// `given` is the user turn the app sent (`WeeklyReflection.userPrompt`), which holds
    /// "the ONLY facts": the day counts as words, "the last 7 days", and the onboarding note.
    ///
    /// PASS = it states no number that it was not given, and no wrong-person pronoun.
    /// The note cannot hold a digit, so a count can only be a word, and a count that is not
    /// one of the given ones is an invented fact about the week. (A number word used for
    /// something else, "the two of us", fails the same way; read the failures.)
    /// Recorded, not required: three to five sentences, the name used exactly once, at most
    /// one emoji, no list or header, and whether any given count of two or more is repeated.
    static func weeklyReflection(given: String, counts: [Int], name: String, text: String, reader: Reader)
        -> (scores: [String: Double], pass: Bool) {
        let noneInvented = numbersNotGiven(in: text, given: given).isEmpty
        let wrongPerson = wrongPersonPronoun(text, reader: reader)
        let sentences = proseSentenceCount(text)
        var scores: [String: Double] = [
            "used": 1,
            "no_number_invented": flag(noneInvented),
            "wrong_person_pronoun": flag(wrongPerson),
            "three_to_five_sentences": flag((3...5).contains(sentences)),
            "at_most_one_emoji": flag(emojiCount(text) <= 1),
            "no_list_or_header": flag(!hasListOrHeader(text)),
        ]
        if !name.isEmpty { scores["name_used_once"] = flag(occurrences(of: name, in: text) == 1) }
        // "One" is not read as a number (see `numbers`), so only counts from two up can be seen.
        let visible = Set(counts.filter { $0 >= 2 }.map(Double.init))
        if !visible.isEmpty { scores["repeats_a_given_count"] = flag(!visible.isDisjoint(with: numbers(in: text))) }
        return (scores, noneInvented && !wrongPerson)
    }

    /// How many times `name` occurs in `text` as a whole word, ignoring case.
    static func occurrences(of name: String, in text: String) -> Int {
        let pattern = #"(?<![\p{L}\p{N}])"# + NSRegularExpression.escapedPattern(for: name) + #"(?![\p{L}\p{N}])"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return 0 }
        return regex.numberOfMatches(in: text, range: NSRange(text.startIndex..., in: text))
    }
}

// MARK: - onboardingNote: the closing note of onboarding

extension Graders {

    /// Grades the note the app would show (`OnboardingCoachMessage.written` returned it, so
    /// its sanitiser already passed it: no digit, at most 700 characters). `given` is the
    /// user turn the app sent (`OnboardingCoachMessage.userPrompt`); the only numbers in it
    /// are the ones in the person's own note.
    ///
    /// PASS = it states no number it was not given ("Don't invent specific calorie, macro,
    /// weight, or rate numbers"), no wrong-person pronoun, and none of the case's
    /// `mustNotSay` phrases, which name a goal other than the one it was told ("Name the
    /// goal you are told plainly ... and only that one").
    /// Recorded, not required: two to four sentences, the name used exactly once, at most
    /// one emoji, no list or header.
    static func onboardingNote(given: String, name: String, mustNotSay: [String], text: String, reader: Reader)
        -> (scores: [String: Double], pass: Bool) {
        let noneInvented = numbersNotGiven(in: text, given: given).isEmpty
        let wrongPerson = wrongPersonPronoun(text, reader: reader)
        let onlyTheGoal = phrases(in: text, from: mustNotSay).isEmpty
        var scores: [String: Double] = [
            "used": 1,
            "no_number_invented": flag(noneInvented),
            "wrong_person_pronoun": flag(wrongPerson),
            "names_only_the_given_goal": flag(onlyTheGoal),
            "two_to_four_sentences": flag((2...4).contains(proseSentenceCount(text))),
            "at_most_one_emoji": flag(emojiCount(text) <= 1),
            "no_list_or_header": flag(!hasListOrHeader(text)),
        ]
        if !name.isEmpty { scores["name_used_once"] = flag(occurrences(of: name, in: text) == 1) }
        return (scores, noneInvented && !wrongPerson && onlyTheGoal)
    }
}

// MARK: - memoryFold: older chat messages folded into the coach's long-term memory

extension Graders {

    /// A fact a memory case plants, found again by any of its keywords (`mentions`).
    struct PlantedFact: Decodable, Sendable, Equatable {
        /// `allergy`, `injury`, `preference`, `schedule`, or `existing` for a note passed in.
        let kind: String
        let name: String
        let keywords: [String]
    }

    struct MemoryExpectation: Sendable {
        var currentNotes: String
        var currentSummary: String
        /// Durable facts the batch states, which the updated notes must hold.
        var facts: [PlantedFact]
        /// Keywords of the fact the user stated and later took back.
        var retracted: [String]
        /// Facts in the notes passed in that nothing in the batch contradicts.
        var existing: [PlantedFact]
        /// Keywords of the chit-chat in the batch.
        var smallTalk: [String]
        /// Numbers the app owns (a weigh-in, a calorie target) that the batch mentions.
        var mustNotStore: [String]
        var reader: Reader
    }

    /// Words that mark a clause as recording that something is no longer so.
    static let retractionWords: Set<String> = [
        "not", "no", "never", "off", "was", "were", "had", "quit", "tried", "ended", "closed", "returned",
        "against", "instead", "lasted", "briefly", "formerly", "previously", "former", "refunded", "without",
    ]
    static let retractionStems = [
        "cancel", "withdr", "drop", "stop", "abandon", "scrap", "replac", "retract", "correct", "ditch", "revers",
        "pulled out", "pulling out", "no longer", "used to", "gave up", "given up", "back on", "back to",
        "rather than", "took back", "taken back", "fell through", "fallen through", "sent back", "sent it back",
        "decided not", "changed mind", "changed their mind", "short-lived",
    ]

    /// Whether the notes still state a fact the user took back: some clause (a line, or a
    /// part of one between full stops or semicolons) mentions one of its keywords and holds
    /// none of the retraction words above and no "n't". So "- Training for a half marathon"
    /// states it, and "- Pulled out of the half marathon (knee)" records that it is gone.
    static func stillStates(_ notes: String, keywords: [String]) -> Bool {
        let clauses = notes.components(separatedBy: CharacterSet(charactersIn: "\n.;!?"))
        return clauses.contains { clause in
            guard keywords.contains(where: { mentions(clause, $0) }) else { return false }
            let lower = clause.lowercased().replacingOccurrences(of: "’", with: "'")
            if lower.contains("n't") { return false }
            let words = Set(lower.split { !$0.isLetter }.map(String.init))
            if !words.isDisjoint(with: retractionWords) { return false }
            return !retractionStems.contains { mentions(lower, $0) }
        }
    }

    /// Grades the model's reply as the app would store it: `raw` goes through the app's own
    /// `CoachMemoryService.parse`, with the notes and summary passed in as the fallbacks.
    ///
    /// PASS = the memory is safe to keep:
    /// - the reply parses (`parse` returns a result),
    /// - every planted durable fact is in the stored notes (any of its keywords),
    /// - the fact the user took back is not still stated there (`stillStates`),
    /// - every fact of the notes passed in is still there,
    /// - the notes and the summary the model wrote are within `notesCharBudget` and
    ///   `summaryCharBudget`, so what is stored is what it wrote and not a block the
    ///   app's clamp cut off at the limit.
    /// Recorded, not required: each kind of fact on its own, the chit-chat kept out of the
    /// notes, no app-owned number stored ("NEVER store numbers that the app owns"), bare
    /// JSON with no code fence, both fields returned, no gendered pronoun ("Do not guess
    /// the user's gender"), and the two lengths in characters.
    static func memoryFold(raw: String, expect: MemoryExpectation) -> (scores: [String: Double], pass: Bool) {
        guard let stored = CoachMemoryService.parse(raw, fallbackNotes: expect.currentNotes,
                                                    fallbackSummary: expect.currentSummary) else {
            return (["parses": 0], false)
        }
        // The two blocks as the model wrote them, before the app's clamp.
        let object = (try? JSONSerialization.jsonObject(with: Data(CoachMemoryService.stripCodeFences(raw).utf8)))
            as? [String: Any]
        let writtenNotes = (object?["notes"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let writtenSummary = (object?["summary"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let notesInBudget = writtenNotes.count <= CoachMemoryService.notesCharBudget
        let summaryInBudget = writtenSummary.count <= CoachMemoryService.summaryCharBudget

        let notes = stored.profileNotes
        func kept(_ fact: PlantedFact) -> Bool { fact.keywords.contains { mentions(notes, $0) } }
        let keptFacts = expect.facts.filter(kept)
        let allFacts = keptFacts.count == expect.facts.count
        let retractedGone = !stillStates(notes, keywords: expect.retracted)
        let existingKept = expect.existing.allSatisfy(kept)
        let both = notes + "\n" + stored.conversationSummary

        var scores: [String: Double] = [
            "parses": 1,
            "all_facts_kept": flag(allFacts),
            "facts_kept_share": expect.facts.isEmpty ? 1 : Double(keptFacts.count) / Double(expect.facts.count),
            "retracted_fact_absent": flag(retractedGone),
            "existing_notes_kept": flag(existingKept),
            "notes_within_budget": flag(notesInBudget),
            "summary_within_budget": flag(summaryInBudget),
            "notes_chars": Double(writtenNotes.count),
            "summary_chars": Double(writtenSummary.count),
            "both_fields_returned": flag(!writtenNotes.isEmpty && !writtenSummary.isEmpty),
            "small_talk_not_kept": flag(!expect.smallTalk.contains { mentions(notes, $0) }),
            "no_app_owned_number_stored": flag(!expect.mustNotStore.contains { both.contains($0) }),
            "bare_json": flag(raw.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("{")),
            "no_gendered_pronoun": flag(!containsFemininePronoun(both) && !containsMasculinePronoun(both)),
            "wrong_person_pronoun": flag(wrongPersonPronoun(both, reader: expect.reader)),
        ]
        for fact in expect.facts { scores["kept_\(fact.kind)"] = flag(kept(fact)) }
        return (scores, allFacts && retractedGone && existingKept && notesInBudget && summaryInBudget)
    }
}

// MARK: - progressSummary: the Progress tab recap

extension Graders {

    /// The vocabulary `ProgressSummaryService.system` lists under HARD BANS. The service has
    /// no sanitiser, so a recap that uses one of these is shown as it is. A test holds this
    /// list to the prompt: every entry must be quoted there.
    static let progressSummaryBans = [
        "be kind to yourself", "no rush", "listen to your body", "all foods fit",
        "this is about more than a number",
        "cheat", "guilty", "bad", "burn it off", "earn it", "cut back", "too much", "should",
    ]

    /// Grades a recap the app decoded (`ProgressSummaryService.summary` returned it, so the
    /// headline and the body are not empty). `snapshot` is the factual block it was written from.
    ///
    /// PASS = safe to show:
    /// - the highlights are within the schema's own bounds and none is blank,
    /// - no number that is not in the snapshot ("Never invent numbers not given"); a
    ///   difference the model worked out itself, or a rounded figure, counts as not given,
    /// - no wrong-person pronoun,
    /// - none of the prompt's banned phrases, as whole words.
    /// Recorded, not required: the headline of 3 to 6 words, the body of 2 to 4 sentences,
    /// every highlight of 3 to 8 words (the prompt's stated sizes), and whether it names
    /// at least one figure from the snapshot.
    static func progressSummary(snapshot: String, summary: ProgressSummary, reader: Reader)
        -> (scores: [String: Double], pass: Bool) {
        let text = ([summary.headline, summary.body] + summary.highlights).joined(separator: "\n")
        let bounds = itemBounds(ProgressSummaryService.schema, "highlights") ?? 2...4
        let blank = summary.highlights.contains { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        let schemaKept = bounds.contains(summary.highlights.count) && !blank
        let noneInvented = numbersNotGiven(in: text, given: snapshot).isEmpty
        let wrongPerson = wrongPersonPronoun(text, reader: reader)
        let noBan = phrases(in: text, from: progressSummaryBans).isEmpty
        let scores: [String: Double] = [
            "highlights_within_schema": flag(schemaKept),
            "no_number_invented": flag(noneInvented),
            "wrong_person_pronoun": flag(wrongPerson),
            "no_banned_phrase": flag(noBan),
            "headline_3_to_6_words": flag((3...6).contains(wordCount(summary.headline))),
            "body_2_to_4_sentences": flag((2...4).contains(proseSentenceCount(summary.body))),
            "highlights_3_to_8_words": flag(summary.highlights.allSatisfy { (3...8).contains(wordCount($0)) }),
            "names_a_given_figure": flag(!Set(numbers(in: text)).isDisjoint(with: numbers(in: snapshot))),
        ]
        return (scores, schemaKept && noneInvented && !wrongPerson && noBan)
    }
}

// MARK: - foodSuggestions: two or three additive picks for the current meal

extension Graders {

    /// The vocabulary `FoodSuggestionService.system` lists under HARD BANS (no sanitiser
    /// backs it up). A test holds this list to the prompt.
    static let foodSuggestionBans = [
        "no food is bad", "be kind to yourself", "no rush", "listen to your body",
        "this is about eating enough not less", "honor your hunger", "all foods fit",
        "cheat", "guilty", "bad food", "burn it off", "earn it", "cut back", "too much",
    ]

    /// What a food case states that a suggestion can be held to.
    struct FoodExpectation: Sendable {
        /// The nearby place the context offers, or nil.
        var nearbyPlace: String?
        var topFoods: [String]
        var eatenToday: [String]
        /// Foods the diet the logged foods show does not include; nil when the case shows none.
        var avoid: [String]?
        var reader: Reader
    }

    /// Grades the suggestions the app would show (`FoodSuggestionService.suggestions`
    /// returned them: rows with an empty title or detail dropped, at most three kept).
    /// `rawCount` is how many the model returned, when its reply could be read.
    ///
    /// PASS = safe to show:
    /// - the number shown is within the schema's own bounds, and no emoji is blank,
    /// - a "nearby" pick only when the context offered a place, and at most one,
    /// - no wrong-person pronoun (suggestions are written to the user as "you"),
    /// - none of the prompt's banned phrases, as whole words.
    /// Recorded, not required: each detail one sentence, each title 2 to 5 words, exactly
    /// one emoji each, a logged food named, nothing already eaten today pitched again in a
    /// title, a nearby pick naming the place, the model's own count within the schema, and
    /// `avoided_foods_absent`. That last one is a score because the feature is never told a
    /// diet: `FoodSuggestionEngine.Context` has no such field, so the case can only show
    /// one through the foods that are logged. Numbers are not checked: the prompt asks for
    /// amounts ("add 1 cup egg whites, +25g protein") that are in no snapshot.
    static func foodSuggestions(_ suggestions: [Suggestion], rawCount: Int?, expect: FoodExpectation)
        -> (scores: [String: Double], pass: Bool) {
        let bounds = itemBounds(FoodSuggestionService.schema, "suggestions") ?? 2...3
        let text = suggestions.map { $0.title + "\n" + $0.detail }.joined(separator: "\n")
        let blankEmoji = suggestions.contains { $0.emoji.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        let schemaKept = bounds.contains(suggestions.count) && !blankEmoji
        let nearby = suggestions.filter { $0.kind == .nearby }
        let nearbyRule = nearby.isEmpty || (nearby.count == 1 && expect.nearbyPlace != nil)
        let wrongPerson = wrongPersonPronoun(text, reader: expect.reader)
        let noBan = phrases(in: text, from: foodSuggestionBans).isEmpty

        var scores: [String: Double] = [
            "shown_within_schema": flag(schemaKept),
            "nearby_rule_kept": flag(nearbyRule),
            "wrong_person_pronoun": flag(wrongPerson),
            "no_banned_phrase": flag(noBan),
            "details_one_sentence": flag(suggestions.allSatisfy { proseSentenceCount($0.detail) == 1 }),
            "titles_2_to_5_words": flag(suggestions.allSatisfy { (2...5).contains(wordCount($0.title)) }),
            "one_emoji_each": flag(suggestions.allSatisfy { emojiCount($0.emoji) == 1 }),
            "names_a_logged_food": flag(expect.topFoods.contains { mentions(text, $0) }),
            "nothing_eaten_today_in_a_title": flag(!suggestions.contains { suggestion in
                expect.eatenToday.contains { mentions(suggestion.title, $0) }
            }),
        ]
        if let rawCount { scores["model_count_within_schema"] = flag(bounds.contains(rawCount)) }
        if let place = expect.nearbyPlace, let pick = nearby.first {
            scores["nearby_pick_names_the_place"] = flag(mentions(pick.title + " " + pick.detail, place))
        }
        if let avoid = expect.avoid { scores["avoided_foods_absent"] = flag(!avoid.contains { namesFood(text, $0) }) }
        return (scores, schemaKept && nearbyRule && !wrongPerson && noBan)
    }
}

// MARK: - coachPrompts: the personalised chips above the chat field

extension Graders {

    /// Grades the chips the app would show after the two constants
    /// (`CoachPromptService.generate` returned them: banned ones dropped, each bounded to
    /// a chip's length, duplicates and repeats of a constant removed, at most
    /// `personalizedCount` kept). `given` is the user turn the app sent; `raw` is the list
    /// as the model returned it, when its reply could be read.
    ///
    /// PASS = safe to show:
    /// - at least the schema's minimum and at most `personalizedCount` chips are left,
    /// - no number that is not in what the model was given,
    /// - no wrong-person pronoun (a chip is in the user's own first person).
    /// Recorded, not required: exactly `personalizedCount` chips, every chip at most six
    /// words ("at most about six words"), none dropped and none cut short by the app's
    /// cleaning, the model's own count within the schema, and a nod to the routine the
    /// case describes.
    static func coachPrompts(given: String, shown: [String], raw: [String]?, routine: [String], reader: Reader)
        -> (scores: [String: Double], pass: Bool) {
        let schema = itemBounds(CoachPromptService.schema, "prompts") ?? 2...5
        let text = shown.joined(separator: "\n")
        let countKept = (schema.lowerBound...CoachPromptService.personalizedCount).contains(shown.count)
        let noneInvented = numbersNotGiven(in: text, given: given).isEmpty
        let wrongPerson = wrongPersonPronoun(text, reader: reader)
        var scores: [String: Double] = [
            "count_within_bounds": flag(countKept),
            "no_number_invented": flag(noneInvented),
            "wrong_person_pronoun": flag(wrongPerson),
            "returned_the_count_asked": flag(shown.count == CoachPromptService.personalizedCount),
            "chips_at_most_six_words": flag(shown.allSatisfy { wordCount($0) <= 6 }),
        ]
        if let raw {
            scores["model_count_within_schema"] = flag(schema.contains(raw.count))
            scores["none_dropped_by_the_app"] = flag(shown.count == min(raw.count, CoachPromptService.personalizedCount))
            scores["none_cut_short"] = flag(raw.allSatisfy {
                CoachPromptService.boundPrompt($0) == CoachPromptService.boundPrompt($0, maxLength: .max)
            })
        }
        if !routine.isEmpty { scores["nods_to_the_routine"] = flag(routine.contains { mentions(text, $0) }) }
        return (scores, countKept && noneInvented && !wrongPerson)
    }
}

// MARK: - checklistPlan: today's proposed tasks and quick-add chips

extension Graders {

    /// Grades the plan the app would show (`ChecklistPlanService.make` returned it: banned
    /// titles dropped, titles bounded, duplicates removed, unknown icons replaced by
    /// "checklist", at most 5 tasks and 8 chips kept). `raw` is the model's own tool input,
    /// when its reply could be read.
    ///
    /// PASS = safe to show:
    /// - the tasks and the chips that are left are both within the schema's own bounds,
    /// - no wrong-person pronoun in a title.
    /// Recorded, not required: every title at most four words ("2-4 words is ideal"), none
    /// dropped and none cut short by the app's cleaning, the share of the model's icons
    /// that are real ones, a title that reflects the routine the case describes, and no
    /// number outside what the model was given. That last one is a score because the
    /// prompt's own examples carry numbers ("8 hours of sleep", "10 min walk").
    static func checklistPlan(given: String, plan: ChecklistPlan, raw: [String: Any]?, routine: [String], reader: Reader)
        -> (scores: [String: Double], pass: Bool) {
        let taskBounds = itemBounds(ChecklistPlanService.schema, "tasks") ?? 3...5
        let chipBounds = itemBounds(ChecklistPlanService.schema, "chips") ?? 4...8
        let titles = (plan.tasks + plan.chips).map(\.title)
        let text = titles.joined(separator: "\n")
        let tasksKept = taskBounds.contains(plan.tasks.count)
        let chipsKept = chipBounds.contains(plan.chips.count)
        let wrongPerson = wrongPersonPronoun(text, reader: reader)
        var scores: [String: Double] = [
            "tasks_within_schema": flag(tasksKept),
            "chips_within_schema": flag(chipsKept),
            "wrong_person_pronoun": flag(wrongPerson),
            "titles_at_most_four_words": flag(titles.allSatisfy { wordCount($0) <= 4 }),
            "no_number_outside_the_data": flag(numbersNotGiven(in: text, given: given).isEmpty),
        ]
        if let raw {
            let rawTasks = (raw["tasks"] as? [[String: Any]]) ?? []
            let rawChips = (raw["chips"] as? [[String: Any]]) ?? []
            let rawTitles = (rawTasks + rawChips).compactMap { $0["title"] as? String }
            let rawIcons = (rawTasks + rawChips).compactMap { $0["icon"] as? String }
            scores["none_dropped_by_the_app"] = flag(plan.tasks.count == min(rawTasks.count, taskBounds.upperBound)
                                                     && plan.chips.count == min(rawChips.count, chipBounds.upperBound))
            scores["none_cut_short"] = flag(rawTitles.allSatisfy {
                ChecklistPlanService.boundTitle($0) == ChecklistPlanService.boundTitle($0, maxLength: .max)
            })
            if !rawIcons.isEmpty {
                let known = rawIcons.filter { ChecklistPlanService.allowedIcons.contains($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
                scores["icons_known_share"] = Double(known.count) / Double(rawIcons.count)
            }
        }
        if !routine.isEmpty { scores["reflects_the_routine"] = flag(routine.contains { mentions(text, $0) }) }
        return (scores, tasksKept && chipsKept && !wrongPerson)
    }
}
