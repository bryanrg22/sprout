import Foundation

/// Reads the rows of a US Nutrition Facts panel below the macros (saturated fat, trans fat,
/// cholesterol, sodium, fiber, total and added sugars, vitamin D, calcium, iron, potassium)
/// out of OCR'd text. `ScanView.parseNutritionLabel` reads calories and the three macros;
/// this reads the rest.
///
/// A row that is not on the label, or whose amount cannot be read with confidence, is left
/// `nil` (not known). The parser never fills a missing row with 0. It returns 0 only when
/// the label prints a zero or says the food is "not a significant source of" the nutrient,
/// which the labelling rule defines as an amount that may be declared as zero
/// (21 CFR 101.9(f)(1); for dietary fiber the same sentence means "less than 1 gram").
///
/// What it tolerates, each with a test in `NutritionLabelDetailParserTests`:
/// - the common wordings ("Sat. Fat", "Dietary Fiber" / "Fibre", "Sugars" for "Total
///   Sugars", "Includes 10g Added Sugars" with the amount BEFORE the name, "Vit. D",
///   "Potas.");
/// - OCR misreads inside an amount (`O`/`Q` for 0, `l`/`I`/`|` for 1, `S` for 5, `B` for 8,
///   so "16Omg" is 160 mg, "Og" is 0 g and "lg" is 1 g) and inside a unit ("meg"/"ug" for
///   mcg, "rng" for mg);
/// - an amount on the line after its name, and a row whose unit was dropped when a
///   % Daily Value still follows it ("Sodium 160 7%");
/// - "less than 1g" / "<5mg", read as half the stated bound (the midpoint of the range the
///   label gives);
/// - a different unit than the US one ("Sodium 0.16g", "Vitamin D 80 IU"), converted.
///
/// What it does not do: read a % Daily Value as an amount, read rows from the ingredient
/// list or the footnote, or work out sodium from a "Salt" row (non-US labels).
enum NutritionLabelDetailParser {

    static func parse(_ rawLines: [String]) -> NutrientDetail {
        // One OCR item can hold several printed lines.
        let lines = rawLines
            .flatMap { $0.components(separatedBy: .newlines) }
            .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
            .filter { !$0.isEmpty }
        guard !lines.isEmpty else { return NutrientDetail() }

        var detail = NutrientDetail()
        for nutrient in Nutrient.allCases {
            if let value = amount(for: nutrient, in: lines) { detail[nutrient] = value }
        }
        // "Not a significant source of …" is how a short label declares the rows it leaves
        // off. For every nutrient but fiber that is an amount that may be declared as zero;
        // for dietary fiber the rule's threshold is "less than 1 gram" (21 CFR 101.9(f)(1)),
        // which is read like any other "less than": half the bound.
        for nutrient in insignificant(in: lines) where detail[nutrient] == nil {
            detail[nutrient] = nutrient == .fiber ? 0.5 : 0
        }
        return detail
    }

    // MARK: - Row names

    /// How each row is found, most specific wording first. The look-behinds keep
    /// "unsaturated" from reading as saturated fat, "insoluble fiber" as fiber, and
    /// "added sugars" or "sugar alcohol" as total sugars.
    private static let names: [Nutrient: [NSRegularExpression]] = namePatterns.mapValues { $0.map(regex) }

    private static let namePatterns: [Nutrient: [String]] = [
        .saturatedFat: [#"(?<![a-z])sat(?:urated|\.)?\s*fat"#, #"(?<![a-z])saturate[ds](?![a-z])"#],
        .transFat: [#"(?<![a-z])trans\s*fat"#, #"(?<![a-z])trans(?![a-z])"#],
        .cholesterol: [#"(?<![a-z])cholest[a-z]*\.?"#],
        .sodium: [#"(?<![a-z])sodium(?![a-z])"#],
        .fiber: [#"(?<!soluble )(?<![a-z])(?:dietary\s+)?fib(?:er|re)(?![a-z])"#],
        .sugars: [#"(?<!added )(?<![a-z])(?:total\s+)?sugars?(?![a-z])(?!\s*alcohol)"#],
        .addedSugars: [#"(?<![a-z])added\s+sugars?(?![a-z])"#],
        .vitaminD: [#"(?<![a-z])vit(?:amin|\.)?\s*d(?![a-z])"#],
        .calcium: [#"(?<![a-z])calcium(?![a-z])"#],
        .iron: [#"(?<![a-z])iron(?![a-z])"#],
        .potassium: [#"(?<![a-z])potas[a-z]*\.?"#],
    ]

    /// Where one row's text ends on a line that OCR merged with the next: the start of any
    /// other row name. Without this "Total Sugars 12 Includes 10g Added Sugars" would give
    /// total sugars the added-sugars amount.
    private static let boundary = regex(
        #"(?<![a-z])(?:total\s+fat|sat(?:urated|\.)?\s*fat|saturate[ds]|trans|cholest|sodium|total\s+carb|carbohydrate|"#
        + #"dietary\s+fib|fib(?:er|re)|total\s+sugar|added\s+sugar|sugars?|includes|incl\.?|protein|"#
        + #"vit(?:amin|\.)|calcium|iron|potas|calories|polyunsat|monounsat)"#)

    /// Lines that name nutrients without being rows: the footnote, the "not a significant
    /// source" sentence (handled on its own), and the ingredient list.
    private static func isNotARow(_ line: String) -> Bool {
        line.contains("daily value") || line.contains("daily diet") || line.contains("calories a day")
            || line.contains("significant source") || line.contains("ingredient")
    }

    // MARK: - One row

    private static func amount(for nutrient: Nutrient, in lines: [String]) -> Double? {
        for name in names[nutrient] ?? [] {
            for (index, line) in lines.enumerated() where !isNotARow(line) {
                guard let match = firstRange(name, in: line) else { continue }
                let after = fragment(of: line, from: match.upperBound)
                var found: Reading?
                if nutrient == .addedSugars {
                    // "Includes 10g Added Sugars": the amount is printed before the name.
                    found = readings(in: fragmentBefore(match.lowerBound, in: line)).last
                }
                found = found ?? readings(in: after).first ?? bareReading(in: after)
                if found == nil, after.trimmingCharacters(in: .whitespaces).isEmpty,
                   index + 1 < lines.count {
                    // The amount on its own line, straight after the name.
                    found = leadingReading(in: lines[index + 1])
                }
                if let found, let value = found.value(in: nutrient) { return value }
            }
        }
        return nil
    }

    /// The text of the row that starts at `start`: up to the next row name on the line.
    private static func fragment(of line: String, from start: String.Index) -> String {
        let rest = line[start...]
        guard let next = firstRange(boundary, in: String(rest)) else { return String(rest) }
        return String(String(rest)[..<next.lowerBound])
    }

    /// The text between the previous row name and `end` (for an amount printed before its name).
    private static func fragmentBefore(_ end: String.Index, in line: String) -> String {
        let head = String(line[..<end])
        let ns = head as NSString
        let matches = boundary.matches(in: head, range: NSRange(location: 0, length: ns.length))
        guard let last = matches.last else { return head }
        return ns.substring(from: last.range.location + last.range.length)
    }

    // MARK: - Amounts

    private enum FoundUnit { case g, mg, mcg, iu }

    private struct Reading {
        var number: Double
        /// `nil` when the row's unit was lost and the label's own unit is assumed.
        var unit: FoundUnit?
        /// "less than" / "<": the label states a bound, not an amount.
        var isBound = false

        /// The amount in the nutrient's own unit, or `nil` when it cannot be that nutrient
        /// (out of range, or a unit the nutrient is never stated in).
        func value(in nutrient: Nutrient) -> Double? {
            var grams: Double
            switch unit {
            case nil: return check(isBound ? number / 2 : number, nutrient)
            case .g: grams = number
            case .mg: grams = number / 1_000
            case .mcg: grams = number / 1_000_000
            case .iu:
                // Only vitamin D is declared in IU on older labels: 40 IU = 1 mcg.
                guard nutrient == .vitaminD else { return nil }
                grams = number / 40 / 1_000_000
            }
            if isBound { grams /= 2 }
            return check(grams * nutrient.unit.perGram, nutrient)
        }

        private func check(_ value: Double, _ nutrient: Nutrient) -> Double? {
            // Trim the float noise unit conversion leaves (0.16 g → 160.00000000000003 mg).
            let tidy = (value * 1_000).rounded() / 1_000
            return nutrient.accepts(tidy) ? tidy : nil
        }
    }

    /// A number with its unit, tolerant of the usual OCR confusions. The number must hold a
    /// real digit, or be a single misread digit (`o`, `l`, `s`…) pressed right against a
    /// mass unit ("Og", "lg", "Omg"); the unit must follow the number, so a word or a
    /// % Daily Value can never be read as an amount.
    private static let amountPattern =
        #"(?<![a-z0-9.,])(<|less\s+than\s*)?\s*"#
        + #"((?:[0-9oqlis|b]*[0-9][0-9oqlis|b]*(?:[.,][0-9oq]{1,3})?)|(?:[oq][.,][0-9][0-9oq]?)"#
        + #"|(?:[oqlis|b](?=(?:mcg|meg|µg|μg|ug|mg|rng|g)(?![a-z]))))"#
        + #"\s*(mcg|meg|µg|μg|ug|mg|rng|iu|g)(?![a-z])"#
    private static let amountRegex = regex(amountPattern)
    private static let leadingAmountRegex = regex(#"^\s*"# + amountPattern)

    /// A number with no unit, alone on its row apart from an optional % Daily Value.
    private static let bareRegex = regex(#"^[\s:.\-]*(\d+(?:\.\d{1,2})?)(?:\s+\d+\s*%)?[\s*†]*$"#)
    /// "1,240": a comma before exactly three digits groups thousands (unless the whole part
    /// is 0, where "0,125" is a decimal); any other comma is a decimal comma.
    private static let thousandsRegex = regex(#"^([1-9][0-9]*),([0-9]{3})$"#)

    private static let digitSwaps: [Character: Character] = [
        "o": "0", "q": "0", "l": "1", "i": "1", "|": "1", "s": "5", "b": "8",
    ]

    private static func readings(in text: String) -> [Reading] {
        let ns = text as NSString
        return amountRegex.matches(in: text, range: NSRange(location: 0, length: ns.length))
            .compactMap { reading(from: $0, in: ns) }
    }

    private static func leadingReading(in line: String) -> Reading? {
        let ns = line as NSString
        return leadingAmountRegex.firstMatch(in: line, range: NSRange(location: 0, length: ns.length))
            .flatMap { reading(from: $0, in: ns) }
    }

    private static func bareReading(in text: String) -> Reading? {
        let ns = text as NSString
        guard let match = bareRegex.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)),
              let number = Double(ns.substring(with: match.range(at: 1))) else { return nil }
        return Reading(number: number, unit: nil)
    }

    private static func reading(from match: NSTextCheckingResult, in ns: NSString) -> Reading? {
        // Letters first (so "1,24O" is seen as 1,240), then the comma's meaning.
        var digits = String(ns.substring(with: match.range(at: 2)).map { $0 == "," ? $0 : (digitSwaps[$0] ?? $0) })
        let whole = NSRange(location: 0, length: (digits as NSString).length)
        if thousandsRegex.firstMatch(in: digits, range: whole) != nil {
            digits = digits.replacingOccurrences(of: ",", with: "")
        } else {
            digits = digits.replacingOccurrences(of: ",", with: ".")
        }
        guard let number = Double(digits) else { return nil }
        let unit: FoundUnit
        switch ns.substring(with: match.range(at: 3)) {
        case "g": unit = .g
        case "mg", "rng": unit = .mg
        case "iu": unit = .iu
        default: unit = .mcg
        }
        return Reading(number: number, unit: unit, isBound: match.range(at: 1).location != NSNotFound)
    }

    // MARK: - "Not a significant source of …"

    /// The nutrients a simplified label declares as zero in its closing sentence. The
    /// sentence usually wraps across lines, so it is read from the joined text up to its
    /// full stop.
    private static func insignificant(in lines: [String]) -> [Nutrient] {
        let blob = lines.joined(separator: " ")
        guard let start = blob.range(of: "not a significant source of") else { return [] }
        var sentence = String(blob[start.upperBound...].prefix(260))
        if let stop = sentence.firstIndex(of: ".") { sentence = String(sentence[..<stop]) }
        return Nutrient.allCases.filter { nutrient in
            (names[nutrient] ?? []).contains { firstRange($0, in: sentence) != nil }
        }
    }

    // MARK: - Regex plumbing

    /// The patterns are literals in this file. One that does not compile is a programming
    /// error (the tests exercise every one); in the field it matches nothing, which leaves
    /// rows unknown rather than stopping the scan.
    private static func regex(_ pattern: String) -> NSRegularExpression {
        (try? NSRegularExpression(pattern: pattern)) ?? NSRegularExpression()
    }

    private static func firstRange(_ regex: NSRegularExpression, in text: String) -> Range<String.Index>? {
        let ns = text as NSString
        guard let match = regex.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)) else { return nil }
        return Range(match.range, in: text)
    }
}
