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
        let workouts = (try? context.fetch(FetchDescriptor<WorkoutEntry>())) ?? []
        let water = (try? context.fetch(FetchDescriptor<WaterEntry>())) ?? []
        let dataSummary = CoachContext.summary(profile: profile, foods: foods, weights: weights,
                                               workouts: workouts, water: water)
        let points = loggedDayCount(foods: foods, weights: weights)

        let coaching = coachingNote(profile: profile, foods: foods, weights: weights)
        let client = try AnthropicClient()
        let result = try await client.structured(
            system: systemPrompt(profile: profile),
            userContent: userContent(dataSummary: dataSummary, intake: intake) + coaching,
            toolName: "write_plan",
            toolDescription: "Author the user's personalized, data-grounded coaching plan.",
            schema: planSchema,
            model: AIConfig.planModel,
            maxTokens: 2200
        )

        let fresh = makePlan(from: result, dataPoints: points)
        // One plan per user. If one exists, rebuild it IN PLACE (same row) rather than
        // delete-and-insert. Deleting the row could (a) tombstone a CoachPlan that an in-flight
        // `review()` is about to mutate across its await, and (b) invalidate the live reference a
        // Vita edit_plan / update_plan Undo closure captured. Mutating in place keeps the row — and
        // every reference to it — valid, and preserves the CloudKit record. A fresh build still
        // replaces all content (changelog + createdAt included — it's a brand-new plan).
        if let existing = CoachPlan.current(in: context) {
            existing.headline = fresh.headline
            existing.assessment = fresh.assessment
            existing.strategy = fresh.strategy
            existing.calorieMin = fresh.calorieMin
            existing.calorieMax = fresh.calorieMax
            existing.proteinTarget = fresh.proteinTarget
            existing.goalSummary = fresh.goalSummary
            existing.timeframe = fresh.timeframe
            existing.dataPointsAtBuild = fresh.dataPointsAtBuild
            existing.insights = fresh.insights
            existing.changelog = fresh.changelog
            existing.createdAt = fresh.createdAt
            existing.updatedAt = fresh.updatedAt
            try? context.save()
            return existing
        }
        context.insert(fresh)
        try? context.save()
        return fresh
    }

    // MARK: - Review (the light "are we on target?" adaptation pass)

    /// Re-read the data against the EXISTING plan and adapt it: nudge the range / protein / insights
    /// only if the data warrants, and append one changelog line describing the change (or noting
    /// "on track"). Lighter than `generate` — no intake free-text, no full re-author; it compares
    /// reality to the plan that's already there. Preserves history: the resulting plan carries the
    /// old changelog with the new entry appended and keeps the original `createdAt`. If there's no
    /// plan yet there's nothing to review, so we fall through to a fresh `generate`.
    /// Anthropic-only (runs on `planModel`). Throws `.missingKey` if no key is set.
    @MainActor
    static func review(profile: UserProfile,
                       foods: [FoodEntry],
                       weights: [WeightEntry],
                       context: ModelContext) async throws -> CoachPlan {
        guard let existing = CoachPlan.current(in: context) else {
            // Nothing to review yet — build one from scratch (no intake words to work from).
            return try await generate(profile: profile, foods: foods, weights: weights,
                                      intake: "", context: context)
        }

        let workouts = (try? context.fetch(FetchDescriptor<WorkoutEntry>())) ?? []
        let water = (try? context.fetch(FetchDescriptor<WaterEntry>())) ?? []
        let dataSummary = CoachContext.summary(profile: profile, foods: foods, weights: weights,
                                               workouts: workouts, water: water)
        let points = loggedDayCount(foods: foods, weights: weights)
        let elapsed = daysSince(existing.updatedAt)

        // Surface beneficial coaching patterns (eat-more-to-perform / ease-off-for-better-results)
        // so the review turns them into encouraging, results-focused insights — never warnings.
        let coaching = coachingNote(profile: profile, foods: foods, weights: weights)

        let client = try AnthropicClient()
        let result = try await client.structured(
            system: reviewSystemPrompt(profile: profile),
            userContent: reviewUserContent(plan: existing, dataSummary: dataSummary, daysSince: elapsed) + coaching,
            toolName: "write_plan",
            toolDescription: "Re-emit the user's plan, adapted to the latest data (same shape as the build).",
            schema: planSchema,
            model: AIConfig.planModel,
            maxTokens: 2200
        )

        // Map the fresh result, then keep history: merge changelogs + carry the original createdAt.
        let fresh = makePlan(from: result, dataPoints: points)
        let merged = mergedChangelog(old: existing.changelog, new: fresh.changelog)

        // Update in place so the row's identity / CloudKit record survives the review.
        existing.headline = fresh.headline
        existing.assessment = fresh.assessment
        existing.strategy = fresh.strategy
        existing.calorieMin = fresh.calorieMin
        existing.calorieMax = fresh.calorieMax
        existing.proteinTarget = fresh.proteinTarget
        existing.goalSummary = fresh.goalSummary
        existing.timeframe = fresh.timeframe
        existing.dataPointsAtBuild = points
        existing.insights = fresh.insights
        existing.changelog = merged
        // createdAt is intentionally left untouched — the plan's birthday doesn't change on review.
        existing.updatedAt = fresh.updatedAt
        try? context.save()
        return existing
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
        "watch" (a gentle flag), or "nudge" (a concrete lever to pull). The most valuable insights catch \
        the patterns that move the goal: under-eating below the floor (a "watch"), protein falling short \
        of target (a "nudge"), a behavior visibly driving an outcome in the data (e.g. "your three \
        highest-protein days were your three biggest drops" — a "win" or "nudge"), and genuine wins \
        worth naming when they're fueling well and the trend agrees (a "win"). Prefer these over generic \
        observations whenever the data supports them.
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

    // MARK: - Review prompts (pure)

    /// The review-pass system prompt: same coaching ethos as the build, but framed as *checking an
    /// existing plan against reality* and adapting it conservatively — change only what the data
    /// warrants, and make the adaptation visible in one changelog line.
    static func reviewSystemPrompt(profile: UserProfile) -> String {
        let name = profile.name.isEmpty ? "the user" : profile.name
        return """
        You are \(name)'s coach, reviewing a plan you already wrote. Compare reality (the latest \
        data) to this existing plan. Is it working?

        Adjust the calorie range / protein / insights ONLY if the data warrants it — don't churn a \
        plan that's on track. Then write ONE new changelog line describing what changed (or say \
        exactly "No change needed — on track" if nothing should change).

        Same rules as always:
        - The calorie target is a RANGE (calorie_min..calorie_max), never a single number — a floor \
        that prevents under-eating and a soft ceiling that keeps the goal on track. Going UNDER the \
        floor is the trap, not extra credit.
        - Be honest but encouraging: if the data drifted off track, say so plainly and give the path \
        back, never discouragement.
        - Be specific to the data — name the numbers, foods, and trend. Generic advice is failure.
        - Confidence scales with data; with few logged days, hedge openly rather than fake precision.
        - 3 to 5 insights, each short and actionable. tone = "win", "watch", or "nudge".
        - assessment and strategy are short markdown for a phone, not an essay.
        - changelog_note is the ONE new line for this review (what changed, or "No change needed — on track").

        Re-emit the FULL plan (every field) by calling write_plan, carrying forward whatever still \
        holds and updating only what the data moved.
        """
    }

    /// The review user turn: the current plan (so the model can compare against it), the fresh data
    /// summary, and how long it's been since the plan was last touched.
    static func reviewUserContent(plan: CoachPlan, dataSummary: String, daysSince: Int) -> String {
        let when: String
        switch daysSince {
        case 0:  when = "today"
        case 1:  when = "1 day ago"
        default: when = "\(daysSince) days ago"
        }
        var out = "Here is the plan you wrote \(when):\n\n"
        out += "Headline: \(plan.headline)\n"
        let range = plan.calorieRangeText
        out += "Calorie range: \(range.isEmpty ? "not set" : "\(range) kcal/day")\n"
        out += "Protein target: \(plan.proteinTarget > 0 ? "\(Int(plan.proteinTarget)) g/day" : "not set")\n"
        if !plan.assessment.isEmpty { out += "Assessment: \(plan.assessment)\n" }
        if plan.insights.isEmpty {
            out += "Insights: (none on the current plan)\n"
        } else {
            out += "Insights:\n"
            for i in plan.insights {
                out += "  - [\(i.tone.rawValue)] \(i.title): \(i.body)\n"
            }
        }
        out += "\nHere is the latest data from the app:\n\n\(dataSummary)\n\n"
        out += "Review it against the plan above and re-emit the plan by calling write_plan."
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
        // Tolerate a swapped range (min > max) from the model — normalize it rather than store it
        // as-is, where `hasRange` would be false and the targets would silently vanish ("not set").
        var cMin = num(result["calorie_min"])
        var cMax = num(result["calorie_max"])
        if cMin > 0, cMax > 0, cMin > cMax { swap(&cMin, &cMax) }
        return CoachPlan(
            headline: str(result["headline"]),
            assessment: str(result["assessment"]),
            strategy: str(result["strategy"]),
            calorieMin: cMin,
            calorieMax: cMax,
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

    /// Merge an existing plan's changelog with a freshly-authored one, preserving full history:
    /// the old entries first (in order), then the new entry/entries appended last. `makePlan` always
    /// stamps exactly one entry for the current pass, so a review yields N+1 lines — and adaptation
    /// stays visible instead of overwriting the past. Pure, so it's testable without the network.
    static func mergedChangelog(old: [PlanChange], new: [PlanChange]) -> [PlanChange] {
        old + new
    }

    /// Whole calendar days between `date` and now (clamped at 0), for the "you wrote this N days ago"
    /// line the review prompt leads with.
    static func daysSince(_ date: Date, now: Date = .now, calendar: Calendar = .current) -> Int {
        let days = calendar.dateComponents([.day],
                                           from: calendar.startOfDay(for: date),
                                           to: calendar.startOfDay(for: now)).day ?? 0
        return max(0, days)
    }

    /// Distinct calendar days with any food OR weight logged — the "how much do we actually know"
    /// signal that drives the plan's confidence hedging.
    static func loggedDayCount(foods: [FoodEntry], weights: [WeightEntry],
                               now: Date = .now, calendar: Calendar = .current) -> Int {
        let today = calendar.startOfDay(for: now)
        var days = Set<Date>()
        // Exclude future-dated entries (clock skew / fat-finger) so they can't inflate the count and
        // wrongly flip `isEarlyRead` — consistent with how the intake average already ignores them.
        for f in foods where calendar.startOfDay(for: f.date) <= today { days.insert(calendar.startOfDay(for: f.date)) }
        for w in weights where calendar.startOfDay(for: w.date) <= today { days.insert(calendar.startOfDay(for: w.date)) }
        return days.count
    }

    // MARK: - Coaching patterns (beneficial teaching moments, NOT safety warnings)

    /// A short directive appended to the plan prompt when HER data shows a pattern worth a BENEFICIAL
    /// teaching moment — e.g. she's eating so little that eating MORE would actually help her results,
    /// or losing so fast that easing off would protect her muscle + momentum. The model turns these
    /// into encouraging, results-focused insights ("here's how this actually helps you"), never
    /// warnings. Empty when nothing stands out. On-ethos: this app teaches + celebrates results — it
    /// is NOT an ED-safety gate. (A live web_search could later enrich the "why" with current research.)
    static func coachingNote(profile: UserProfile, foods: [FoodEntry], weights: [WeightEntry],
                             now: Date = .now, calendar: Calendar = .current) -> String {
        let flags = coachingFlags(profile: profile, foods: foods, weights: weights, now: now, calendar: calendar)
        guard !flags.isEmpty else { return "" }
        return "\n\nPATTERNS WORTH A TEACHING MOMENT — turn each into a beneficial, results-focused insight "
            + "(the encouraging \"here's how this actually helps you\" angle; never a warning or shame):\n- "
            + flags.joined(separator: "\n- ")
    }

    /// Data-driven coaching patterns — notable things in HER logged data that make for a beneficial,
    /// educational insight. Pure + testable.
    static func coachingFlags(profile: UserProfile, foods: [FoodEntry], weights: [WeightEntry],
                              now: Date = .now, calendar: Calendar = .current) -> [String] {
        var flags: [String] = []

        // Eating very little → the "eat MORE to get better results" teaching moment.
        let floor = profile.sex == .female ? 1200.0 : 1500.0
        let daily = recentDailyCalories(foods, days: 7, now: now, calendar: calendar)
        // Need ≥3 logged days before calling intake "low": averaging over 1–2 days (or a single
        // breakfast-only day) makes under-LOGGING look like under-EATING and fires a false "eat more"
        // moment. Mirrors the ≥3 guard the rate branch below uses.
        if daily.count >= 3 {
            let avg = daily.reduce(0, +) / Double(daily.count)
            if avg > 0 && avg < floor {
                flags.append("Her logged intake is averaging only ~\(Int(avg.rounded())) kcal/day. If that's real "
                    + "(not just unlogged meals), eating a bit MORE would likely help her results — more energy to "
                    + "train, it protects muscle in a deficit, and it's more sustainable. Teach that benefit warmly.")
            }
        }

        // Losing very fast → the "ease off a touch for better, lasting results" teaching moment (loss only).
        // Only real (non-future-dated) weigh-ins: a single future-dated entry (clock skew / fat-finger)
        // would otherwise slide TrendCalculator's window into the future and skew the rate.
        let realWeights = weights.filter { $0.date <= now }
        if profile.pace.direction == .lose, realWeights.count >= 3 {
            let rate = TrendCalculator.ratePerWeek(realWeights)   // negative = losing
            if rate < -2.0 {
                flags.append("She's losing fast — about \(String(format: "%.1f", abs(rate))) lb/week. Easing the "
                    + "deficit a little would protect her muscle and make the loss actually stick — frame it as "
                    + "getting BETTER results, not a problem.")
            }
        }
        return flags
    }

    /// Per-day total calories for the days that have food logged, within the last `days` days.
    private static func recentDailyCalories(_ foods: [FoodEntry], days: Int,
                                            now: Date, calendar: Calendar) -> [Double] {
        let start = calendar.startOfDay(for: now)
        guard let cutoff = calendar.date(byAdding: .day, value: -(days - 1), to: start) else { return [] }
        var byDay: [Date: Double] = [:]
        for f in foods {
            let d = calendar.startOfDay(for: f.date)
            guard d >= cutoff, d <= start else { continue }
            byDay[d, default: 0] += f.totalCalories
        }
        return Array(byDay.values)
    }

    private static func str(_ v: Any?) -> String { (v as? String) ?? "" }

    private static func num(_ v: Any?) -> Double {
        if let d = v as? Double { return d }
        if let i = v as? Int { return Double(i) }
        if let n = v as? NSNumber { return n.doubleValue }
        if let s = v as? String {
            let t = s.trimmingCharacters(in: .whitespaces)
            if let d = Double(t) { return d }
            // Salvage a number from a messy string ("1,600 kcal", "~1600", "-50"): keep digits, the
            // FIRST dot, and a leading sign — so the sign isn't dropped and a stray second dot can't
            // poison the parse. (Dead today: JSONSerialization hands numbers back as NSNumber.)
            var out = "", seenDot = false
            for ch in t {
                if ch.isNumber { out.append(ch) }
                else if ch == "." && !seenDot { out.append(ch); seenDot = true }
                else if ch == "-" && out.isEmpty { out.append(ch) }
            }
            return Double(out) ?? 0
        }
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
