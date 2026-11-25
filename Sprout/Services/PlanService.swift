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
    /// Runs on the active provider's heavy tier (`AIConfig.planModel`: Opus on Anthropic, the
    /// strong GPT tier on OpenAI). Throws `.missingKey` if the active provider has no key.
    @MainActor
    static func generate(profile: UserProfile,
                         foods: [FoodEntry],
                         weights: [WeightEntry],
                         intake: String,
                         context: ModelContext) async throws -> CoachPlan {
        // Real Workouts-tab data (sessions + per-machine exercises). The legacy `WorkoutEntry` is
        // debug-only, so fetching it left the AI plan blind to her actual training.
        let sessions = (try? context.fetch(FetchDescriptor<WorkoutSession>())) ?? []
        let exercises = (try? context.fetch(FetchDescriptor<ExerciseEntry>())) ?? []
        let water = (try? context.fetch(FetchDescriptor<WaterEntry>())) ?? []
        let dataSummary = CoachContext.summary(profile: profile, foods: foods, weights: weights,
                                               water: water, sessions: sessions, exercises: exercises)
        let points = loggedDayCount(foods: foods, weights: weights)

        let coaching = coachingNote(profile: profile, foods: foods, weights: weights)
        let client = try AIClient.makeFull()

        // PHASE 1 — ground the heavy BUILD in current, cited evidence via a live web search,
        // on whichever provider is active. Best-effort: if the key's plan doesn't allow web
        // search (or it errors), we build from her data + the model's knowledge alone. The
        // REVIEW pass stays web-free by design (it reasons over her latest data).
        let research = await researchGrounding(profile: profile, intake: intake)

        // PHASE 2 — author the structured plan, now grounded in the research.
        let result = try await client.structured(
            system: systemPrompt(profile: profile),
            userContent: userContent(dataSummary: dataSummary, intake: intake, about: profile.onboardingNote) + coaching + research.grounding,
            toolName: "write_plan",
            toolDescription: "Author the user's personalized, data-grounded coaching plan.",
            schema: planSchema,
            model: AIConfig.model(for: .planBuild),
            maxTokens: 2200
        )

        // A blank answer must never replace a plan (EVAL_REPORT 40): nothing is touched.
        try requireUsable(result)
        let fresh = makePlan(from: result, dataPoints: points)
        // Fold the model's structured profile summary into her editable "About You" (the single
        // canonical bio every coach surface reads) — this is why the plan-intake answers now show
        // up in Settings → About You instead of vanishing into Vita's hidden memory. Only overwrite
        // when the model actually returned one.
        let aboutYou = str(result["about_you"]).trimmingCharacters(in: .whitespacesAndNewlines)
        if !aboutYou.isEmpty { profile.onboardingNote = aboutYou }
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
            existing.researchNotes = research.notes   // the cited brief that grounded this build
            try? context.save()
            existing.clearGoalsChanged()              // built against the goals as they are now
            existing.anchorTargets(to: profile.pace.direction)   // its numbers are for this direction
            PlanTargetSync.apply(plan: existing, to: profile)    // and drive the targets from here
            return existing
        }
        fresh.researchNotes = research.notes
        context.insert(fresh)
        try? context.save()
        fresh.clearGoalsChanged()
        fresh.anchorTargets(to: profile.pace.direction)
        PlanTargetSync.apply(plan: fresh, to: profile)
        return fresh
    }

    // MARK: - Review (the light "are we on target?" adaptation pass)

    /// Re-read the data against the EXISTING plan and adapt it: nudge the range / protein / insights
    /// only if the data warrants, and append one changelog line describing the change (or noting
    /// "on track"). Lighter than `generate` — no intake free-text, no full re-author; it compares
    /// reality to the plan that's already there. Preserves history: the resulting plan carries the
    /// old changelog with the new entry appended and keeps the original `createdAt`. If there's no
    /// plan yet there's nothing to review, so we fall through to a fresh `generate`.
    /// Provider-aware (runs on `planModel`). Throws `.missingKey` if the active provider has no key.
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

        // Real Workouts-tab data (sessions + per-machine exercises). The legacy `WorkoutEntry` is
        // debug-only, so fetching it left the AI plan blind to her actual training.
        let sessions = (try? context.fetch(FetchDescriptor<WorkoutSession>())) ?? []
        let exercises = (try? context.fetch(FetchDescriptor<ExerciseEntry>())) ?? []
        let water = (try? context.fetch(FetchDescriptor<WaterEntry>())) ?? []
        let dataSummary = CoachContext.summary(profile: profile, foods: foods, weights: weights,
                                               water: water, sessions: sessions, exercises: exercises)
        let points = loggedDayCount(foods: foods, weights: weights)
        let elapsed = daysSince(existing.updatedAt)

        // Surface beneficial coaching patterns (eat-more-to-perform / ease-off-for-better-results)
        // so the review turns them into encouraging, results-focused insights — never warnings.
        let coaching = coachingNote(profile: profile, foods: foods, weights: weights)

        let client = try AIClient.makeFull()
        let result = try await client.structured(
            system: reviewSystemPrompt(profile: profile),
            userContent: reviewUserContent(plan: existing, dataSummary: dataSummary, daysSince: elapsed, about: profile.onboardingNote) + coaching,
            toolName: "write_plan",
            toolDescription: "Re-emit the user's plan, adapted to the latest data (same shape as the build).",
            schema: planSchema,
            model: AIConfig.model(for: .planReview),
            maxTokens: 2200
        )

        // A blank answer must never overwrite the plan it was reviewing (EVAL_REPORT 40).
        try requireUsable(result)
        // Map the fresh result, then keep history: merge changelogs + carry the original createdAt.
        let fresh = makePlan(from: result, dataPoints: points)
        // Keep her editable About You in sync as the plan adapts (the canonical bio all surfaces read).
        let aboutYou = str(result["about_you"]).trimmingCharacters(in: .whitespacesAndNewlines)
        if !aboutYou.isEmpty { profile.onboardingNote = aboutYou }
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
        - If CURRENT RESEARCH is provided below, ground your numbers in it and briefly name the source \
        (e.g. "current guidance puts protein around…") — it's there so they can trust the plan, not just \
        take your word. Don't cite for its own sake; weave it in where it sharpens a target.
        - changelog_note is one line summarizing what this build set up.
        - about_you is a clean, organized profile summary (third-person notes) of who they are — \
        routine/schedule, training, food habits + preferences, constraints, and motivation — \
        synthesized from their own words and their data. NOT a greeting or a verbatim echo. Carry \
        forward whatever still holds from their existing About You (shown below if present). This is \
        saved as their editable About You and read by every coach surface, so make it accurate, \
        durable, and kind.
        """
    }

    /// The data + the user's own intake words, handed to the model as the user turn.
    static func userContent(dataSummary: String, intake: String, about: String = "") -> String {
        let trimmed = intake.trimmingCharacters(in: .whitespacesAndNewlines)
        var out = "Here is everything I know about them from the app:\n\n\(dataSummary)"
        let bio = about.trimmingCharacters(in: .whitespacesAndNewlines)
        if !bio.isEmpty {
            out += "\n\nTheir current About You profile (keep whatever still holds and refine it for about_you):\n\"\(bio)\""
        }
        if !trimmed.isEmpty {
            out += "\n\nAnd here is what they told me, in their own words, about their goals and life:\n\"\(trimmed)\""
        } else {
            out += "\n\n(They didn't add extra context in their own words — work from the data above.)"
        }
        out += "\n\nAuthor their plan now by calling write_plan."
        return out
    }

    // MARK: - Research phase (web-search grounding — heavy build only)

    /// Run the live-web research phase and format it for the write_plan turn. Best-effort: returns
    /// "" (an un-grounded build) on any failure, and never throws — plan creation must not depend on
    /// web search being available. Logged so the diagnostics panel shows whether it actually searched.
    /// Provider-aware: Anthropic's `web_search` server tool or OpenAI's Responses `web_search`,
    /// following the Settings pick like every other AI call.
    @MainActor
    static func researchGrounding(profile: UserProfile, intake: String) async -> (grounding: String, notes: String) {
        // Response-level cache first: same goal (direction + 10-lb band) within 30 days
        // → reuse the stored brief instead of re-running the most expensive call in the
        // app. A direction flip or big goal move misses naturally and researches fresh.
        let cacheKey = ResearchCache.key(direction: profile.pace.direction,
                                         goalWeightLbs: profile.goalWeightLbs)
        if let cached = ResearchCache.lookup(key: cacheKey) {
            Diagnostics.shared.log("plan research: cache hit (\(cached.count) chars, ≤\(ResearchCache.ttlDays)d old)", .ai)
            return (groundingText(from: cached), cached)
        }

        let system = researchSystemPrompt(profile: profile)
        let user = researchUserContent(profile: profile, intake: intake)
        let research: (text: String, usedSearch: Bool)?
        switch AIConfig.provider {
        case .anthropic:
            research = try? await AnthropicClient().research(system: system, userContent: user,
                                                             model: AIConfig.model(for: .planResearch))
        case .openai:
            research = try? await OpenAIClient().research(system: system, userContent: user,
                                                          model: AIConfig.model(for: .planResearch))
        }
        guard let research, !research.text.isEmpty else {
            Diagnostics.shared.log("plan research: none (web search unavailable or empty)", .ai)
            return ("", "")
        }
        Diagnostics.shared.log("plan research: \(research.usedSearch ? "searched · " : "")\(research.text.count) chars", .ai)
        if research.usedSearch { ResearchCache.store(research.text, key: cacheKey) }
        return (groundingText(from: research.text), research.text)
    }

    /// The prompt block that folds a research brief (fresh or cached) into the build.
    private static func groundingText(from brief: String) -> String {
        "\n\nCURRENT RESEARCH (from a live web search) to ground your plan — use it, and briefly "
            + "name the source where you lean on it so they can trust the numbers:\n\(brief)"
    }

    /// The research-phase system prompt: a meticulous coach searching the live web for the few current,
    /// reputable facts that make THIS plan more accurate than generic knowledge. Pure + testable.
    static func researchSystemPrompt(profile: UserProfile) -> String {
        let name = profile.name.isEmpty ? "this person" : profile.name
        return """
        You are a meticulous nutrition + training researcher prepping to write \(name)'s plan. Search \
        the web for CURRENT, reputable evidence (recent guidelines, well-regarded sources) that bears on \
        their specific goal and situation. Return a TIGHT, factual brief — the few numbers and principles \
        a great coach would look up first — and name your sources inline. No plan yet, no fluff: just the \
        grounded findings.
        """
    }

    /// The research user turn: the direction + her own words, so the searches are about HER goal. Pure.
    static func researchUserContent(profile: UserProfile, intake: String) -> String {
        let direction: String
        switch profile.pace.direction {
        case .lose:     direction = "sustainable fat loss"
        case .gain:     direction = "a healthy lean gain"
        case .maintain: direction = "maintaining a healthy weight"
        }
        var out = "Research current, citable evidence to ground a plan for someone whose goal is \(direction). "
        out += "Focus on what actually moves this goal: a realistic rate of change, protein and calorie targets, "
        out += "and anything specific to their situation below."
        let trimmed = intake.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            out += "\n\nTheir own words about their goal + life:\n\"\(trimmed)\""
        }
        out += "\n\nReturn the cited findings now (no plan yet)."
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
        - about_you: carry forward their existing About You profile (shown below), refining it only if \
        the data or their situation clearly changed. Keep it clean third-person profile notes, not a greeting.

        Re-emit the FULL plan (every field) by calling write_plan, carrying forward whatever still \
        holds and updating only what the data moved.
        """
    }

    /// The review user turn: the current plan (so the model can compare against it), the fresh data
    /// summary, and how long it's been since the plan was last touched.
    static func reviewUserContent(plan: CoachPlan, dataSummary: String, daysSince: Int, about: String = "") -> String {
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
        let bio = about.trimmingCharacters(in: .whitespacesAndNewlines)
        if !bio.isEmpty {
            out += "Their current About You profile (carry forward what still holds, refine for about_you):\n\"\(bio)\"\n\n"
        }
        out += "Review it against the plan above and re-emit the plan by calling write_plan."
        return out
    }

    // MARK: - Result → model (pure)

    /// Map a validated `write_plan` result into a `CoachPlan`. Tolerant of missing/loosely-typed
    /// fields (numbers may arrive as Int/Double/String). Stamps one changelog entry for this build.
    /// Whether a reply is a plan at all: a headline, an assessment, a calorie range and a
    /// protein target. claude-opus-5-5 once answered with every field empty and every number
    /// 0 (1 of 30 builds, EVAL_REPORT 40), which `makePlan` would have stored over the
    /// person's plan. The schema cannot forbid empty strings and zeros on every wire.
    static func isUsable(_ result: [String: Any]) -> Bool {
        !str(result["headline"]).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !str(result["assessment"]).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && num(result["calorie_min"]) > 0 && num(result["calorie_max"]) > 0
            && num(result["protein_target"]) > 0
    }

    /// Throws, before anything is stored, when the reply is not a plan.
    static func requireUsable(_ result: [String: Any]) throws {
        guard isUsable(result) else {
            Diagnostics.shared.log("plan: the model returned an empty plan; nothing was changed", .ai)
            throw AIConfig.AIError.decoding("the plan came back empty")
        }
    }

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
                let why = profile.pace.direction == .gain
                    ? "a gain is built from fuel, so there is nothing to build with at this intake"
                    : "more energy to train, it protects muscle in a deficit, and it's more sustainable"
                flags.append("Their logged intake is averaging only ~\(Int(avg.rounded())) kcal/day. If that's real "
                    + "(not just unlogged meals), eating a bit MORE would likely help their results — \(why). "
                    + "Teach that benefit warmly.")
            }
        }

        // Losing very fast → the "ease off a touch for better, lasting results" teaching moment (loss only).
        // Only real (non-future-dated) weigh-ins: a single future-dated entry (clock skew / fat-finger)
        // would otherwise slide TrendCalculator's window into the future and skew the rate.
        let realWeights = weights.filter { $0.date <= now }
        if profile.pace.direction == .lose, realWeights.count >= 3 {
            let rate = TrendCalculator.ratePerWeek(realWeights)   // negative = losing
            if rate < -2.0 {
                flags.append("They're losing fast — about \(String(format: "%.1f", abs(rate))) lb/week. Easing the "
                    + "deficit a little would protect their muscle and make the loss actually stick — frame it as "
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
            "about_you": ["type": "string", "description": "A clean, organized, notes-style summary of WHO THIS PERSON IS, for durable coaching context — their routine/schedule, training, food habits + preferences, constraints, and what motivates them. Third-person profile notes (NOT a greeting, NOT a verbatim echo of their words). 2-4 short sentences or compact lines. Synthesized from their own words + their data; carry forward anything still true from their existing About You. This becomes their editable 'About You' profile that every part of the app reads."],
        ],
        "required": ["headline", "assessment", "strategy", "calorie_min", "calorie_max", "protein_target", "insights", "changelog_note", "about_you"],
    ]
}
