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

        var confidenceLevel: EstimateConfidence { EstimateConfidence(rawValue: confidence) ?? .low }
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
        ],
        "required": ["items", "total_calories", "calories_low", "calories_high",
                     "total_protein_g", "total_carbs_g", "total_fat_g", "confidence", "notes"],
    ]

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
    """
}
