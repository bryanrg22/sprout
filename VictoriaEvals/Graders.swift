import Foundation
import ImageIO
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

    // MARK: - A generated character image (the `Avatar` evaluation)

    /// What the code can tell about a character image without a person looking at it.
    /// Likeness, and fit with the two existing characters, are the owner's own rating.
    struct ImageMetrics: Equatable {
        var decodable = false
        var width = 0
        var height = 0
        var hasAlpha = false
        /// Every pixel of the two TOP corner blocks is clear. This is the background check
        /// that decides a pass: the style is a bust cut off by the bottom edge, so shoulders
        /// may rightly reach the bottom corners (the second built-in character's do).
        var transparentTopCorners = false
        /// Every pixel of all four corner blocks is clear. Recorded, not required.
        var transparentCorners = false
        /// Share of pixels with alpha exactly 0.
        var transparentShare = 0.0
        /// Distinct colours among the opaque pixels after quantisation (see `distinctColours`).
        var distinctColours = 0

        var isSquare1024: Bool { width == 1024 && height == 1024 }
    }

    /// Side of each corner block checked for transparency, as a share of the image side.
    static let cornerBlockShare = 0.03
    /// Bits kept per channel when counting colours: 4 bits = 16 levels = 4,096 possible colours.
    static let colourBits = 4
    /// A quantised colour counts only if it covers at least this share of the opaque pixels,
    /// so a handful of stray anti-aliased pixels do not look like extra palette entries.
    static let minColourShare = 0.002
    /// At or under this many colours the image is taken to be flat-palette pixel art. The
    /// prompt asks for 12 to 16; a photograph or a painted illustration quantises to
    /// hundreds. NOT calibrated on real outputs yet: the first live run should look at the
    /// distribution of `distinct_colours` before this number is trusted.
    static let pixelArtColourLimit = 48

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
                    for x in x0..<(x0 + block) where pixels.alpha(x: x, y: y) != 0 { return false }
                }
            }
        }
        return true
    }

    /// Colours among the fully opaque pixels, each channel cut to `colourBits` bits, counting
    /// only colours that cover at least `minColourShare` of them.
    static func distinctColours(_ pixels: AvatarImage.Pixels, bits: Int = colourBits,
                                minShare: Double = minColourShare) -> Int {
        let shift = UInt8(8 - bits)
        var counts: [UInt32: Int] = [:]
        var opaque = 0
        var index = 0
        while index < pixels.bytes.count {
            if pixels.bytes[index + 3] == 255 {
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
