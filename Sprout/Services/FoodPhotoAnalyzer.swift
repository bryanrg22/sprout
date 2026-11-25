import Foundation

/// Estimates calories + macros from a meal photo using the active provider's vision
/// model with forced structured output (Claude or GPT — the wire translation lives in
/// the clients). Portion size is the biggest error source, so we ask for a range +
/// confidence and surface "estimate, edit me" in the UI.
struct FoodPhotoAnalyzer {

    struct Estimate: Codable {
        struct Item: Codable {
            var name: String
            var estimated_grams: Double
            var calories: Double
            var protein_g: Double
            var carbs_g: Double
            var fat_g: Double
            var assumptions: String
        }
        var items: [Item]
        var total_calories: Double
        var calories_low: Double
        var calories_high: Double
        var total_protein_g: Double
        var total_carbs_g: Double
        var total_fat_g: Double
        var confidence: String
        var notes: String

        // The four label nutrients a model may estimate (`Nutrient.estimable`), for the whole
        // meal. Each is `nil` when the model said it does not know, when an older response
        // lacks the field, or when what arrived is a placeholder (`init(from:)` below). A
        // `nil` is carried to the entry as "not known" and is never counted as zero.
        var total_fiber_g: Double? = nil
        var total_sugars_g: Double? = nil
        var total_saturated_fat_g: Double? = nil
        var total_sodium_mg: Double? = nil

        var confidenceLevel: EstimateConfidence { EstimateConfidence(rawValue: confidence) ?? .low }

        /// The estimated label nutrients as the entry stores them. Only the four above can
        /// be set: added sugars, trans fat, cholesterol and the vitamins and minerals are
        /// never estimated (`docs/nutrition-detail.md` section 5).
        var detail: NutrientDetail {
            var d = NutrientDetail()
            d.fiberG = total_fiber_g
            d.sugarsG = total_sugars_g
            d.saturatedFatG = total_saturated_fat_g
            d.sodiumMg = total_sodium_mg
            return d
        }
    }

    private static let system = """
    You are a nutrition estimation assistant. Estimate the food in the photo and \
    report it by calling the `log_food` tool — return ONLY the tool call, with no \
    other text or explanation.
    For each item: identify it, then estimate its portion in grams. PORTION SIZE IS THE \
    #1 SOURCE OF ERROR, so anchor the scale to something concrete in the image — the \
    plate or bowl diameter (a dinner plate is ~27cm, a side plate ~20cm), a fork (~19cm), \
    a hand, or a standard can — and reason about pile height/depth and any occluded food, \
    not just the visible top layer. In each item's `assumptions`, name the scale cue you \
    used (e.g. "plate ~27cm", "fork for scale"). Assume restaurant/takeout portions are \
    GENEROUS (larger than home-cooked). For fried, sautéed, roasted, or dressed dishes, \
    add a realistic cooking-oil / butter / sauce / dressing allowance even when it isn't \
    directly visible (this hidden fat is the classic blind spot), and for drinks account \
    for added sugar. Give a calorie RANGE (low/high) and an honest confidence (use "low" \
    when the dish is mixed, occluded, plated unusually, or ambiguous). Do not invent \
    precision you don't have. Keep each `assumptions` value to one short phrase, and keep \
    `notes` to one short sentence.
    \(detailInstruction)
    """

    /// The same paragraph in both prompts. It asks for exactly `Nutrient.estimable` and
    /// gives the model a legal way to say it does not know, so it never has to invent a
    /// number to satisfy the schema.
    private static let detailInstruction = """
    Also report four more totals for the whole meal: `total_fiber_g`, `total_sugars_g` (all \
    sugars, natural and added), `total_saturated_fat_g` and `total_sodium_mg`. Work each \
    out from the foods and portions you identified, the same way as the macros. Each of the \
    four may be null: write null when you have no real basis for it (for example sodium \
    when you cannot tell how a dish was seasoned). Never write 0 as a placeholder: 0 means \
    the meal truly contains none. Do not report any other nutrient.
    """

    private static let schema: [String: Any] = [
        "type": "object",
        "properties": [
            "items": [
                "type": "array",
                "items": [
                    "type": "object",
                    "properties": [
                        "name": ["type": "string"],
                        "estimated_grams": ["type": "number"],
                        "calories": ["type": "number"],
                        "protein_g": ["type": "number"],
                        "carbs_g": ["type": "number"],
                        "fat_g": ["type": "number"],
                        "assumptions": ["type": "string"],
                    ],
                    "required": ["name", "estimated_grams", "calories", "protein_g", "carbs_g", "fat_g", "assumptions"],
                ],
            ],
            "total_calories": ["type": "number"],
            "calories_low": ["type": "number"],
            "calories_high": ["type": "number"],
            "total_protein_g": ["type": "number"],
            "total_carbs_g": ["type": "number"],
            "total_fat_g": ["type": "number"],
            "confidence": ["type": "string", "enum": ["low", "medium", "high"]],
            "notes": ["type": "string"],
            // Number or null, and REQUIRED. Required-and-nullable is how an optional field is
            // written so that it means the same on every provider: OpenAI's strict mode makes
            // every property required anyway and would fill a plain optional number with a
            // placeholder (EVAL_REPORT 10); with null allowed, "I don't know" has a spelling.
            "total_fiber_g": nullableAmount("Dietary fiber in the whole meal, grams. null if you have no basis."),
            "total_sugars_g": nullableAmount("Total sugars (natural and added) in the whole meal, grams. null if you have no basis."),
            "total_saturated_fat_g": nullableAmount("Saturated fat in the whole meal, grams. null if you have no basis."),
            "total_sodium_mg": nullableAmount("Sodium in the whole meal, MILLIGRAMS. null if you have no basis."),
        ],
        "required": ["items", "total_calories", "calories_low", "calories_high",
                     "total_protein_g", "total_carbs_g", "total_fat_g", "confidence", "notes",
                     "total_fiber_g", "total_sugars_g", "total_saturated_fat_g", "total_sodium_mg"],
    ]

    private static func nullableAmount(_ description: String) -> [String: Any] {
        ["type": ["number", "null"], "description": description]
    }

    /// The schema as sent, for tests.
    static var estimateSchema: [String: Any] { schema }

    static func analyze(imageData: Data, userNote: String?) async throws -> Estimate {
        try await analyze(imagesData: [imageData], userNote: userNote)
    }

    /// Estimate ONE meal that may be spread across several photos (different items,
    /// plates, or angles). All images go in a single request so the model returns one
    /// combined total rather than us summing separate guesses.
    static func analyze(imagesData: [Data], userNote: String?) async throws -> Estimate {
        var prompt: String
        if imagesData.count > 1 {
            prompt = "These \(imagesData.count) photos all show the SAME meal (different items or angles). "
                + "Identify every distinct food across them WITHOUT double-counting an item that appears in more "
                + "than one photo, and return ONE combined estimate for the whole meal."
        } else {
            prompt = "Estimate the calories and macros for this meal."
        }
        if let n = userNote, !n.isEmpty { prompt += " The user adds: \"\(n)\"." }
        var content: [[String: Any]] = imagesData.map { AnthropicClient.imageBlock($0) }
        content.append(AnthropicClient.textBlock(prompt))
        return try await run(task: .mealPhoto, system: system, content: content)
    }

    /// Text-only estimate from a spoken/typed description ("a Chipotle chicken burrito with
    /// guac") — same structured output as the photo path, no image needed. For when there's
    /// no photo, or it's faster to just say what you ate.
    static func analyze(description: String) async throws -> Estimate {
        let content: [[String: Any]] = [
            AnthropicClient.textBlock("Estimate the calories and macros for this meal: \"\(description)\"."),
        ]
        return try await run(task: .mealDescribe, system: describeSystem, content: content)
    }

    /// Shared call + decode for both the photo and text paths.
    private static func run(task: AITask, system: String, content: [[String: Any]]) async throws -> Estimate {
        let client = try AIClient.makeFull()
        let dict = try await client.structured(
            system: system,
            userContent: content,
            toolName: "log_food",
            toolDescription: "Record the estimated nutrition for the food.",
            schema: schema,
            model: AIConfig.model(for: task),
            maxTokens: 2048
        )
        let data = try JSONSerialization.data(withJSONObject: dict)
        do { return try JSONDecoder().decode(Estimate.self, from: data) }
        catch { throw AIConfig.AIError.decoding(String(describing: error)) }
    }

    private static let describeSystem = """
    You are a nutrition estimation assistant. Estimate the food the user DESCRIBES and report \
    it by calling the `log_food` tool — return ONLY the tool call, with no other text. \
    Identify each item and estimate a realistic portion in grams: for a named brand or \
    restaurant item (e.g. "Chipotle chicken burrito") use that chain's typical serving; \
    otherwise assume a standard home portion unless the user specifies size. Account for \
    hidden oils, butter, sauces, dressings, and added sugar in drinks. PORTION is the #1 \
    error source, so give a calorie RANGE (low/high) and an honest confidence (use "low" when \
    the description is vague or sizes are unstated). Do not invent precision. Keep each \
    `assumptions` value to one short phrase, and keep `notes` to one short sentence.
    \(detailInstruction)
    """
}

// MARK: - Decoding

extension FoodPhotoAnalyzer.Estimate {

    /// Its own key type, so the synthesized `encode(to:)` keeps deriving its keys from the
    /// stored properties.
    private enum Key: String, CodingKey {
        case items, total_calories, calories_low, calories_high
        case total_protein_g, total_carbs_g, total_fat_g, confidence, notes
        case total_fiber_g, total_sugars_g, total_saturated_fat_g, total_sodium_mg
    }

    /// The nine original fields decode strictly, as before: an estimate missing one is an
    /// error and is never logged. The four label nutrients decode leniently, because "not
    /// known" is a legitimate answer for each of them.
    ///
    /// How "not known" arrives, and what is treated as it:
    /// - `null`, the documented way (the schema types each as number-or-null and lists it as
    ///   required, which is also how OpenAI's strict mode spells an optional field);
    /// - the key missing altogether (a response from before these fields existed, or a
    ///   non-strict provider that left it out);
    /// - a placeholder: a negative number, a non-number ("", "unknown", "n/a"), or an amount
    ///   beyond `Nutrient.plausibleMax`;
    /// - an amount that cannot be true of this meal: more saturated fat than fat, more fiber
    ///   plus sugars than carbohydrate, or no saturated fat at all in 10 g or more of fat;
    /// - all four exactly 0 on a meal of 50 kcal or more: indistinguishable from a model
    ///   filling required fields, so none of the four is believed.
    ///
    /// In every one of those cases the field is `nil`. Declared in an extension so the
    /// memberwise initializer stays available.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Key.self)
        self.init(
            items: try c.decode([Item].self, forKey: .items),
            total_calories: try c.decode(Double.self, forKey: .total_calories),
            calories_low: try c.decode(Double.self, forKey: .calories_low),
            calories_high: try c.decode(Double.self, forKey: .calories_high),
            total_protein_g: try c.decode(Double.self, forKey: .total_protein_g),
            total_carbs_g: try c.decode(Double.self, forKey: .total_carbs_g),
            total_fat_g: try c.decode(Double.self, forKey: .total_fat_g),
            confidence: try c.decode(String.self, forKey: .confidence),
            // One sentence of prose, shown only when present: a reply without it (claude-haiku-5-5
            // sent one in 66, EVAL_REPORT 37) keeps its calories and macros.
            notes: (try? c.decodeIfPresent(String.self, forKey: .notes)) ?? "",
            total_fiber_g: Self.amount(c, .total_fiber_g, .fiber),
            total_sugars_g: Self.amount(c, .total_sugars_g, .sugars),
            total_saturated_fat_g: Self.amount(c, .total_saturated_fat_g, .saturatedFat),
            total_sodium_mg: Self.amount(c, .total_sodium_mg, .sodium))
        dropWhatCannotBeTrue()
    }

    /// A known, plausible amount, or `nil`. Never throws: a malformed optional field must
    /// not cost the user the calories and macros that did arrive.
    private static func amount(_ c: KeyedDecodingContainer<Key>, _ key: Key,
                               _ nutrient: Nutrient) -> Double? {
        guard c.contains(key), (try? c.decodeNil(forKey: key)) == false else { return nil }
        let number: Double?
        if let d = try? c.decode(Double.self, forKey: key) {
            number = d
        } else if let text = try? c.decode(String.self, forKey: key) {
            // Some models quote numbers. "unknown", "n/a" and "" are not numbers and fall out.
            number = Double(text.trimmingCharacters(in: .whitespaces))
        } else {
            number = nil
        }
        guard let number, nutrient.accepts(number) else { return nil }
        return number
    }

    /// Applies the "cannot be true of this meal" rules. `mutating`, and also callable on an
    /// estimate built in memory, so the rules have one home.
    mutating func dropWhatCannotBeTrue() {
        // First, on the values as they arrived: four exact zeros on a real meal is the shape
        // of a model filling required fields, and none of the four is believed.
        let four = [total_fiber_g, total_sugars_g, total_saturated_fat_g, total_sodium_mg]
        if total_calories >= 50, four.allSatisfy({ $0 == 0 }) {
            total_fiber_g = nil
            total_sugars_g = nil
            total_saturated_fat_g = nil
            total_sodium_mg = nil
            return
        }

        // A part cannot exceed its whole. The slack covers rounding of small amounts.
        func exceeds(_ part: Double, _ whole: Double) -> Bool { part > whole * 1.1 + 1 }

        if let sat = total_saturated_fat_g {
            // Every dietary fat is at least about 6% saturated, so 10 g of fat with none is
            // a placeholder, not a measurement.
            if exceeds(sat, total_fat_g) || (sat == 0 && total_fat_g >= 10) { total_saturated_fat_g = nil }
        }
        if let fiber = total_fiber_g, exceeds(fiber, total_carbs_g) { total_fiber_g = nil }
        if let sugars = total_sugars_g, exceeds(sugars, total_carbs_g) { total_sugars_g = nil }
        if let fiber = total_fiber_g, let sugars = total_sugars_g, exceeds(fiber + sugars, total_carbs_g) {
            total_fiber_g = nil
            total_sugars_g = nil
        }
    }
}
