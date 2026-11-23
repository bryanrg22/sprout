import Foundation

/// The Nutrition Facts lines beyond calories, protein, carbohydrate and fat, in the order
/// the US label prints them (21 CFR 101.9(c); `docs/nutrition-detail.md` section 1).
///
/// The rule every use of these rests on: **a value that is not known is `nil`, is shown as
/// unknown, and is never counted as zero.** `0` means the source said zero.
enum Nutrient: String, CaseIterable, Codable, Identifiable, Sendable {
    case saturatedFat, transFat, cholesterol, sodium
    case fiber, sugars, addedSugars
    case vitaminD, calcium, iron, potassium

    var id: String { rawValue }

    enum Unit: String, Sendable {
        case g, mg, mcg
        /// How many of this unit make one gram (Open Food Facts states every mass in grams).
        var perGram: Double {
            switch self {
            case .g: return 1
            case .mg: return 1_000
            case .mcg: return 1_000_000
            }
        }
    }

    /// The unit the US label declares the nutrient in, and the unit it is stored in.
    var unit: Unit {
        switch self {
        case .saturatedFat, .transFat, .fiber, .sugars, .addedSugars: return .g
        case .cholesterol, .sodium, .calcium, .iron, .potassium: return .mg
        case .vitaminD: return .mcg
        }
    }

    var label: String {
        switch self {
        case .saturatedFat: return "Saturated fat"
        case .transFat: return "Trans fat"
        case .cholesterol: return "Cholesterol"
        case .sodium: return "Sodium"
        case .fiber: return "Fiber"
        case .sugars: return "Total sugars"
        case .addedSugars: return "Added sugars"
        case .vitaminD: return "Vitamin D"
        case .calcium: return "Calcium"
        case .iron: return "Iron"
        case .potassium: return "Potassium"
        }
    }

    /// The macro row this line is printed under on the label, when it is a part of one.
    enum Parent: Sendable { case fat, carbs, sugars }
    var parent: Parent? {
        switch self {
        case .saturatedFat, .transFat: return .fat
        case .fiber, .sugars: return .carbs
        case .addedSugars: return .sugars
        default: return nil
        }
    }

    /// The argument name in the coach's food tools and the column name in the evaluation
    /// dataset: the nutrient with its unit, so a number can never be read in the wrong one.
    var argumentName: String {
        switch self {
        case .saturatedFat: return "saturated_fat_g"
        case .transFat: return "trans_fat_g"
        case .cholesterol: return "cholesterol_mg"
        case .sodium: return "sodium_mg"
        case .fiber: return "fiber_g"
        case .sugars: return "sugars_g"
        case .addedSugars: return "added_sugars_g"
        case .vitaminD: return "vitamin_d_mcg"
        case .calcium: return "calcium_mg"
        case .iron: return "iron_mg"
        case .potassium: return "potassium_mg"
        }
    }

    /// The most one serving can plausibly hold, in `unit`. A value above it is a parse or
    /// unit error (grams read as milligrams, a % Daily Value read as an amount) and is
    /// refused or dropped by every source rather than stored.
    var plausibleMax: Double {
        switch self {
        case .saturatedFat: return 500
        case .transFat: return 100
        case .cholesterol: return 5_000
        case .sodium: return 50_000
        case .fiber: return 300
        case .sugars, .addedSugars: return 1_000
        case .vitaminD: return 2_500
        case .calcium: return 10_000
        case .iron: return 500
        case .potassium: return 20_000
        }
    }

    /// True for a finite amount between zero and `plausibleMax`.
    func accepts(_ value: Double) -> Bool {
        value.isFinite && value >= 0 && value <= plausibleMax
    }

    /// The four a model may ESTIMATE from a photo or a description, because they follow
    /// from which food it is and how much of it there is, like the macros do. Everything
    /// else is stored only when a label, a database or the user states it
    /// (`docs/nutrition-detail.md` section 5).
    static let estimable: [Nutrient] = [.saturatedFat, .sodium, .fiber, .sugars]

    /// The lines always given a row, known or not. The rest appear once something states them.
    static let core: [Nutrient] = [.saturatedFat, .sodium, .fiber, .sugars, .addedSugars]

    // MARK: Display

    /// "18 g", "0.5 g", "1,240 mg", "2.5 mcg": one decimal below ten when there is one to
    /// show, whole numbers from ten up (the label itself is no finer than that).
    func format(_ value: Double, locale: Locale = .current) -> String {
        "\(Self.number(value, locale: locale)) \(unit.rawValue)"
    }

    static func number(_ value: Double, locale: Locale = .current) -> String {
        let tenths = (value * 10).rounded() / 10
        let shown = tenths >= 10 ? tenths.rounded() : tenths
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = shown == shown.rounded() ? 0 : 1
        return formatter.string(from: NSNumber(value: shown)) ?? String(shown)
    }
}

/// One food's label nutrients, each known or not. A plain value, so the same shape carries
/// a draft, a database hit, a tool edit and a saved entry.
struct NutrientDetail: Equatable, Codable, Sendable {
    var saturatedFatG: Double?
    var transFatG: Double?
    var cholesterolMg: Double?
    var sodiumMg: Double?
    var fiberG: Double?
    var sugarsG: Double?
    var addedSugarsG: Double?
    var vitaminDMcg: Double?
    var calciumMg: Double?
    var ironMg: Double?
    var potassiumMg: Double?

    init() {}

    init(_ values: [Nutrient: Double]) {
        for (nutrient, value) in values { self[nutrient] = value }
    }

    subscript(nutrient: Nutrient) -> Double? {
        get {
            switch nutrient {
            case .saturatedFat: return saturatedFatG
            case .transFat: return transFatG
            case .cholesterol: return cholesterolMg
            case .sodium: return sodiumMg
            case .fiber: return fiberG
            case .sugars: return sugarsG
            case .addedSugars: return addedSugarsG
            case .vitaminD: return vitaminDMcg
            case .calcium: return calciumMg
            case .iron: return ironMg
            case .potassium: return potassiumMg
            }
        }
        set {
            switch nutrient {
            case .saturatedFat: saturatedFatG = newValue
            case .transFat: transFatG = newValue
            case .cholesterol: cholesterolMg = newValue
            case .sodium: sodiumMg = newValue
            case .fiber: fiberG = newValue
            case .sugars: sugarsG = newValue
            case .addedSugars: addedSugarsG = newValue
            case .vitaminD: vitaminDMcg = newValue
            case .calcium: calciumMg = newValue
            case .iron: ironMg = newValue
            case .potassium: potassiumMg = newValue
            }
        }
    }

    /// The nutrients this food states, in label order.
    var known: [Nutrient] { Nutrient.allCases.filter { self[$0] != nil } }
    var isEmpty: Bool { known.isEmpty }

    /// Every known value times `factor`; an unknown stays unknown.
    func scaled(by factor: Double) -> NutrientDetail {
        var out = NutrientDetail()
        for nutrient in Nutrient.allCases {
            if let value = self[nutrient] { out[nutrient] = value * factor }
        }
        return out
    }

    /// "saturated fat 3 g, sodium 480 mg, fiber 4 g": the known values times `quantity`, in
    /// label order, or `nil` when nothing is known. A nutrient that is not known is left out
    /// rather than written as 0, so a reader (the coach) cannot mistake it for none.
    func summary(quantity: Double = 1, locale: Locale = .current) -> String? {
        let parts = known.compactMap { nutrient -> String? in
            self[nutrient].map { "\(nutrient.label.lowercased()) \(nutrient.format($0 * quantity, locale: locale))" }
        }
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }

    /// `other`'s known values laid over this one's; what `other` does not state is kept.
    func merging(_ other: NutrientDetail) -> NutrientDetail {
        var out = self
        for nutrient in Nutrient.allCases {
            if let value = other[nutrient] { out[nutrient] = value }
        }
        return out
    }
}

/// What a set of foods adds up to for each label nutrient, and how much of the set the
/// sum covers. A total is the sum over the foods that state the nutrient; it is `nil`,
/// never zero, when none does, and it is `isComplete` only when every food states it.
struct NutrientTotals: Equatable, Sendable {

    struct Line: Equatable, Identifiable, Sendable {
        let nutrient: Nutrient
        /// Per-serving value × servings, summed over the foods that state it.
        let total: Double?
        /// How many of the foods state it.
        let known: Int
        /// How many foods there are.
        let foods: Int

        var id: String { nutrient.rawValue }
        var isComplete: Bool { foods > 0 && known == foods }

        /// "from 4 of 6 foods"; `nil` when every food contributed, since nothing is missing.
        var coverageNote: String? {
            guard foods > 0, known < foods else { return nil }
            if known == 0 { return foods == 1 ? "not known for this food" : "not known for any of \(foods) foods" }
            return "from \(known) of \(foods) foods"
        }

        /// "18 g", or `nil` when no food states it.
        func valueText(locale: Locale = .current) -> String? {
            total.map { nutrient.format($0, locale: locale) }
        }

        /// "Fiber, 18 grams", or "Fiber, not known".
        var spokenValue: String {
            guard let total else { return "\(nutrient.label), not known" }
            let unit: String
            switch nutrient.unit {
            case .g: unit = "grams"
            case .mg: unit = "milligrams"
            case .mcg: unit = "micrograms"
            }
            return "\(nutrient.label), \(Nutrient.number(total)) \(unit)"
        }

        /// One spoken sentence: "Fiber, 18 grams, from 4 of 6 foods".
        var spoken: String {
            guard total != nil, let note = coverageNote else { return spokenValue }
            return "\(spokenValue), \(note)"
        }
    }

    /// How many foods were added up.
    let foods: Int
    /// One line per nutrient, in label order.
    let lines: [Line]

    init(_ items: [(detail: NutrientDetail, quantity: Double)]) {
        foods = items.count
        lines = Nutrient.allCases.map { nutrient in
            var sum = 0.0
            var known = 0
            for item in items {
                guard let value = item.detail[nutrient] else { continue }
                sum += value * item.quantity
                known += 1
            }
            return Line(nutrient: nutrient, total: known > 0 ? sum : nil, known: known, foods: items.count)
        }
    }

    subscript(nutrient: Nutrient) -> Line {
        // `lines` holds every case in `allCases` order by construction.
        lines[Nutrient.allCases.firstIndex(of: nutrient) ?? 0]
    }

    /// The lines to show: the core ones always, the rest once any food states them.
    var displayed: [Line] {
        lines.filter { Nutrient.core.contains($0.nutrient) || $0.known > 0 }
    }

    /// True when no food states anything.
    var isEmpty: Bool { lines.allSatisfy { $0.known == 0 } }
}

extension NutrientTotals {
    init(_ entries: [FoodEntry]) {
        self.init(entries.map { (detail: $0.detail, quantity: $0.quantity) })
    }
}
