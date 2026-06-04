import Foundation
import SwiftData

/// Builds + adapts the user's adaptive **Plan** (see `docs/adaptive-plan.md`).
///
/// The heavy "deep research" pass hands Opus the full picture — profile, goal, timeframe, the
/// intake free-text, and a summary of every logged day — and gets back a structured plan (via
/// forced tool use, so the shape is guaranteed). The pure pieces here (schema, prompts, and the
/// result→`CoachPlan` mapping) are split out so they can be unit-tested without the network.
enum PlanService {

    // MARK: - Generate (the one-time heavy build)

    /// Author a fresh plan from everything we know, persist it (replacing any prior plan), return it.
    /// Anthropic-only (runs on Opus, like Vita's tool use). Throws `.missingKey` if no key is set.
    @MainActor
    static func generate(profile: UserProfile,
                         foods: [FoodEntry],
                         weights: [WeightEntry],
                         intake: String,
                         context: ModelContext) async throws -> CoachPlan {
        let dataSummary = CoachContext.summary(profile: profile, foods: foods, weights: weights)
        let points = loggedDayCount(foods: foods, weights: weights)

        let client = try AnthropicClient()
        let result = try await client.structured(
            system: systemPrompt(profile: profile),
            userContent: userContent(dataSummary: dataSummary, intake: intake),
            toolName: "write_plan",
            toolDescription: "Author the user's personalized, data-grounded coaching plan.",
            schema: planSchema,
            model: AIConfig.planModel,
            maxTokens: 2200
        )

        let plan = makePlan(from: result, dataPoints: points)
        // One plan per user — replace any prior one.
        if let existing = CoachPlan.current(in: context) { context.delete(existing) }
        context.insert(plan)
        try? context.save()
        return plan
    }

    // MARK: - Prompts (pure)

    /// The coaching philosophy + output contract. Encodes the app's ethos: specific-to-her-data,
    /// range targets, honest-but-never-shaming, educate-don't-refuse, confidence that scales with data.
    static func systemPrompt(profile: UserProfile) -> String {
        let name = profile.name.isEmpty ? "the user" : profile.name
        let direction: String
        switch profile.pace.direction {
        case .lose:     direction = "sustainable fat loss"
        case .gain:     direction = "a healthy lean gain"
        case .maintain: direction = "maintaining a healthy weight"
        }
        return """
        You are an elite, evidence-based nutrition and training coach authoring a PERSONAL plan for \
        \(name), whose goal is \(direction). You think like the best human coaches: grounded in real \
        physiology, honest, encouraging, never shaming, never restrictive.

        Make the plan SPECIFIC to this person's real data and their own words — never generic. Every \
        insight must be something only someone who actually read their logged days could say (name the \
        numbers, the foods, the trend). Generic advice is failure.

        Hard rules:
        - Daily calorie target is a RANGE (calorie_min..calorie_max), never a single number: a floor that \
        prevents under-eating and a soft ceiling that keeps the goal on track. Hitting the range is the \
        win — for a loss goal, going UNDER the floor is the trap, not extra credit.
        - Be honest about whether the data says they're on track, but always frame it as a path forward, \
        never discouragement. If their timeframe is aggressive, say so plainly and give the realistic version.
        - Confidence scales with data. With only a few logged days, hedge openly ("early read — I'll sharpen \
        this as more days come in"). Never fake precision.
        - Educate, don't refuse. If they're drawn to an extreme (barely eating, crash dieting), explain why \
        it backfires and teach the better path — never lecture or shut them down.
        - 3 to 5 insights, each short, specific, and actionable. tone = "win" (celebrate something real), \
        "watch" (a gentle flag), or "nudge" (a concrete lever to pull).
        - assessment and strategy are short markdown for a phone — a few warm, plain sentences or bullets, \
        not an essay.
        - changelog_note is one line summarizing what this build set up.
        """
    }

    /// The data + the user's own intake words, handed to the model as the user turn.
    static func userContent(dataSummary: String, intake: String) -> String {
        let trimmed = intake.trimmingCharacters(in: .whitespacesAndNewlines)
        var out = "Here is everything I know about them from the app:\n\n\(dataSummary)"
        if !trimmed.isEmpty {
            out += "\n\nAnd here is what they told me, in their own words, about their goals and life:\n\"\(trimmed)\""
        } else {
            out += "\n\n(They didn't add extra context in their own words — work from the data above.)"
        }
        out += "\n\nAuthor their plan now by calling write_plan."
        return out
    }

    // MARK: - Result → model (pure)

    /// Map a validated `write_plan` result into a `CoachPlan`. Tolerant of missing/loosely-typed
    /// fields (numbers may arrive as Int/Double/String). Stamps one changelog entry for this build.
    static func makePlan(from result: [String: Any], dataPoints: Int, now: Date = .now) -> CoachPlan {
        let insights = (result["insights"] as? [[String: Any]] ?? []).compactMap { d -> PlanInsight? in
            guard let title = (d["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !title.isEmpty,
                  let body = d["body"] as? String else { return nil }
            let tone = PlanInsight.Tone(rawValue: (d["tone"] as? String) ?? "nudge") ?? .nudge
            return PlanInsight(title: title, body: body, tone: tone)
        }
        let note = (result["changelog_note"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "Plan created."
        return CoachPlan(
            headline: str(result["headline"]),
            assessment: str(result["assessment"]),
            strategy: str(result["strategy"]),
            calorieMin: num(result["calorie_min"]),
            calorieMax: num(result["calorie_max"]),
            proteinTarget: num(result["protein_target"]),
            goalSummary: str(result["goal_summary"]),
            timeframe: str(result["timeframe"]),
            dataPointsAtBuild: dataPoints,
            insights: insights,
            changelog: [PlanChange(date: now, summary: note)],
            createdAt: now,
            updatedAt: now
        )
    }

    // MARK: - Helpers

    /// Distinct calendar days with any food OR weight logged — the "how much do we actually know"
    /// signal that drives the plan's confidence hedging.
    static func loggedDayCount(foods: [FoodEntry], weights: [WeightEntry],
                               calendar: Calendar = .current) -> Int {
        var days = Set<Date>()
        for f in foods { days.insert(calendar.startOfDay(for: f.date)) }
        for w in weights { days.insert(calendar.startOfDay(for: w.date)) }
        return days.count
    }

    private static func str(_ v: Any?) -> String { (v as? String) ?? "" }

    private static func num(_ v: Any?) -> Double {
        if let d = v as? Double { return d }
        if let i = v as? Int { return Double(i) }
        if let n = v as? NSNumber { return n.doubleValue }
        if let s = v as? String { return Double(s.filter { $0.isNumber || $0 == "." }) ?? 0 }
        return 0
    }

    // MARK: - Output schema (forced tool use)

    static let planSchema: [String: Any] = [
        "type": "object",
        "properties": [
            "headline": ["type": "string", "description": "One short line, e.g. 'On track for 135 by September'."],
            "assessment": ["type": "string", "description": "Short markdown: the current read on whether they're on track, from the data."],
            "strategy": ["type": "string", "description": "Short markdown: the approach + the WHY behind the targets."],
            "calorie_min": ["type": "number", "description": "Lower bound of the daily calorie range (the floor)."],
            "calorie_max": ["type": "number", "description": "Upper bound of the daily calorie range (the soft ceiling)."],
            "protein_target": ["type": "number", "description": "Daily protein target in grams."],
            "goal_summary": ["type": "string", "description": "Their goal in one short phrase."],
            "timeframe": ["type": "string", "description": "Their timeframe in one short phrase, e.g. 'by end of summer'."],
            "insights": [
                "type": "array",
                "description": "3-5 specific, data-grounded insight cards.",
                "items": [
                    "type": "object",
                    "properties": [
                        "title": ["type": "string"],
                        "body": ["type": "string"],
                        "tone": ["type": "string", "enum": ["win", "watch", "nudge"]],
                    ],
                    "required": ["title", "body", "tone"],
                ],
            ],
            "changelog_note": ["type": "string", "description": "One line: what this build set up."],
        ],
        "required": ["headline", "assessment", "strategy", "calorie_min", "calorie_max", "protein_target", "insights", "changelog_note"],
    ]
}
