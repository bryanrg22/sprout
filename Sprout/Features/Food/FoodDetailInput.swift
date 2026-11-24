import Foundation

/// The label-nutrient text fields of the add/edit sheet, as pure functions: what a saved
/// value looks like in its field, and what a field's text is saved as.
///
/// An empty field is **not known** and is saved as `nil`. `0` is a real zero. Nothing here
/// ever turns "blank" into 0.
enum FoodDetailInput {

    /// The field text for each known value. A nutrient that is not known has no entry, so
    /// its field starts empty.
    static func text(for detail: NutrientDetail) -> [Nutrient: String] {
        var out: [Nutrient: String] = [:]
        for nutrient in detail.known {
            if let value = detail[nutrient] { out[nutrient] = string(value) }
        }
        return out
    }

    /// Up to two decimals, without trailing zeros: 4 → "4", 0.5 → "0.5", 1.13 → "1.13".
    /// POSIX formatting, so the text parses back with `value(_:for:)` in any locale.
    static func string(_ value: Double) -> String {
        let rounded = (value * 100).rounded() / 100
        var text = String(format: "%.2f", locale: Locale(identifier: "en_US_POSIX"), rounded)
        while text.hasSuffix("0") { text.removeLast() }
        if text.hasSuffix(".") { text.removeLast() }
        return text
    }

    /// What a field's text is saved as: `nil` for blank (not known), the number for a
    /// plausible amount, and `nil` for anything else (see `isInvalid`).
    static func value(_ text: String, for nutrient: Nutrient) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        // A decimal pad types "," in many regions.
        guard let number = Double(trimmed.replacingOccurrences(of: ",", with: ".")),
              nutrient.accepts(number) else { return nil }
        return number
    }

    /// True when the field holds text that is not a savable amount (not a number, negative,
    /// or beyond `plausibleMax`). The sheet marks the row and does not save until it is fixed,
    /// so a typo is never stored and never silently dropped.
    static func isInvalid(_ text: String, for nutrient: Nutrient) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && value(trimmed, for: nutrient) == nil
    }

    static func hasInvalid(_ fields: [Nutrient: String]) -> Bool {
        fields.contains { isInvalid($0.value, for: $0.key) }
    }

    static func detail(from fields: [Nutrient: String]) -> NutrientDetail {
        var out = NutrientDetail()
        for (nutrient, text) in fields {
            out[nutrient] = value(text, for: nutrient)
        }
        return out
    }
}
