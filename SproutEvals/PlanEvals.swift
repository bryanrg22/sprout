import Foundation
import SwiftData
import XCTest
@testable import Sprout

/// The three adaptive-plan tasks (`docs/adaptive-plan.md`), each through the app's own code:
///
/// - **planBuild** (`Evals/datasets/plan_build/v1.jsonl`): authoring a new plan from the person's
///   data and the words they typed into the intake sheet. `PlanService.generate` cannot skip its
///   research phase (and that phase reads and writes `ResearchCache` in `UserDefaults.standard`),
///   so the build is run from the building blocks `generate` itself calls, with the research
///   grounding EMPTY: the model being measured is the one that writes the plan, not the one that
///   searched. Where this differs from `generate`, exactly:
///   1. the user turn ends with `""` where `generate` appends `research.grounding` (the app sends
///      `""` too whenever the research phase returns nothing);
///   2. the tool name, tool description and `maxTokens` are literals inside `generate`, so they
///      are repeated in `PlanBuildCall`; `PlanEvalDatasetChecks` holds them to `PlanService.swift`;
///   3. the intake string is composed as `PlanIntakeView.build()` composes it (a private method),
///      also held to the view's source by `PlanEvalDatasetChecks`;
///   4. the data summary is built from the case's arrays rather than fetched from a store (the
///      same `CoachContext.summary` call with the same arguments; no per-machine exercises);
///   5. nothing is persisted: the reply goes through `PlanService.makePlan` (what would be
///      stored) and stops there, so About You, `PlanTargetSync`, the direction anchors and the
///      goals-changed flag (the last two live in `UserDefaults`) are never touched.
/// - **planReview** (`plan_review/v1.jsonl`): `PlanService.review` itself, unchanged, against an
///   in-memory store holding the case's existing plan and logs. The profile's target overrides are
///   set as `PlanTargetSync` would mirror them from that plan (through its pure `overrides`, not
///   `apply`, which records direction anchors in `UserDefaults`). The review has no research phase.
/// - **planResearch** (the `plan_build` cases): the research phase on its own, the same two pure
///   prompts and the same client call `PlanService.researchGrounding` makes, but never reading or
///   writing `ResearchCache` (a cache hit would measure nothing, and a store would leak into the
///   simulator's app state). Records whether it searched, how many searches it ran (priced at
///   $10 per 1,000) and how many sources it cited.
///
/// Rule scores only; quality is for `Evals/judge.py`. The pass rules are written beside each grader.
extension LiveEvals {

    // MARK: - The literals of generate's write_plan call that it does not expose

    enum PlanBuildCall {
        static let toolName = "write_plan"
        static let toolDescription = "Author the user's personalized, data-grounded coaching plan."
        static let maxTokens = 2200
    }

    // MARK: - Cases

    /// A `plan_build` row: the person, their logs, and the three intake boxes as they typed them.
    struct PlanBuildCase: Decodable, Sendable, PlanEvalPerson {
        let id: String
        let user: String
        let pace: String?
        let goalWeight: Double?
        let startWeight: Double?
        let activity: String?
        let bio: String?
        let log: PlanEvalLog?
        let timeframe: String
        let dayToDay: String
        let exercise: String
        /// What a good plan does here, for a person reading the results and the rubric's author.
        let goodPlan: String

        /// The string `PlanIntakeView.build()` hands to `generate` for a new plan.
        var intake: String {
            """
            Timeframe: \(timeframe.trimmingCharacters(in: .whitespacesAndNewlines))
            Day-to-day: \(dayToDay.trimmingCharacters(in: .whitespacesAndNewlines))
            Exercise & schedule: \(exercise.trimmingCharacters(in: .whitespacesAndNewlines))
            """
        }

        var problem: String? { personProblem }
    }

    /// A `plan_review` row: the person, the plan in force (fields as `CoachPlan` stores them),
    /// how long ago it was last touched, and the logs as they stand now.
    struct PlanReviewCase: Decodable, Sendable, PlanEvalPerson {
        struct Insight: Decodable, Sendable {
            let title: String
            let body: String
            /// `win`, `watch` or `nudge`.
            let tone: String
        }
        struct Change: Decodable, Sendable {
            let daysAgo: Int
            let summary: String
        }
        struct Plan: Decodable, Sendable {
            let headline: String
            let assessment: String
            let strategy: String
            let calorieMin: Double
            let calorieMax: Double
            let proteinTarget: Double
            let goalSummary: String
            let timeframe: String
            let dataPointsAtBuild: Int
            let createdDaysAgo: Int
            let insights: [Insight]
            let changelog: [Change]
        }

        let id: String
        let user: String
        let pace: String?
        let goalWeight: Double?
        let startWeight: Double?
        let activity: String?
        let bio: String?
        let log: PlanEvalLog?
        let plan: Plan
        /// Days since the plan's `updatedAt` (what the review prompt leads with).
        let daysSincePlan: Int
        /// How the range should move, judged by its midpoint (±50 kcal is "held"): `hold`, `raise`,
        /// `lower`, `notRaise` or `notLower`; absent when any move is defensible. Only the
        /// `range_moved_as_expected` score reads it; it never decides the pass.
        let expectRange: String?
        let goodReview: String

        static let rangeExpectations: Set<String> = ["hold", "raise", "lower", "notRaise", "notLower"]

        var problem: String? {
            if let problem = personProblem { return problem }
            if daysSincePlan < 0 || plan.createdDaysAgo < daysSincePlan {
                return "daysSincePlan must be 0...createdDaysAgo"
            }
            if let expectRange = expectRange, !Self.rangeExpectations.contains(expectRange) {
                return "expectRange \(expectRange) is not one of \(Self.rangeExpectations.sorted())"
            }
            if plan.calorieMin <= 0 || plan.calorieMax < plan.calorieMin { return "the plan's range is not a range" }
            if plan.insights.contains(where: { PlanInsight.Tone(rawValue: $0.tone) == nil }) {
                return "an insight tone is not win, watch or nudge"
            }
            if plan.changelog.contains(where: { $0.daysAgo < 0 }) { return "a changelog line is in the future" }
            return nil
        }

        /// The plan as the store would hold it, dated relative to `now`.
        func coachPlan(now: Date) -> CoachPlan {
            let calendar = Calendar.current
            func ago(_ days: Int) -> Date { calendar.date(byAdding: .day, value: -days, to: now) ?? now }
            return CoachPlan(
                headline: plan.headline, assessment: plan.assessment, strategy: plan.strategy,
                calorieMin: plan.calorieMin, calorieMax: plan.calorieMax, proteinTarget: plan.proteinTarget,
                goalSummary: plan.goalSummary, timeframe: plan.timeframe, dataPointsAtBuild: plan.dataPointsAtBuild,
                insights: plan.insights.map {
                    PlanInsight(title: $0.title, body: $0.body, tone: PlanInsight.Tone(rawValue: $0.tone) ?? .nudge)
                },
                changelog: plan.changelog.map { PlanChange(date: ago($0.daysAgo), summary: $0.summary) },
                createdAt: ago(plan.createdDaysAgo), updatedAt: ago(daysSincePlan))
        }
    }

    // MARK: - Tests

    func testPlanBuild() async throws {
        try EvalEnv.requireLive()
        let cases = try EvalDataset.load("plan_build/v1.jsonl", as: PlanBuildCase.self)
        try await EvalRunner.run(task: .planBuild, dataset: "plan_build/v1", cases: cases,
                                 caseID: { $0.id }) { item in
            await Self.planBuildAttempt(item)
        }
    }

    func testPlanReview() async throws {
        try EvalEnv.requireLive()
        let cases = try EvalDataset.load("plan_review/v1.jsonl", as: PlanReviewCase.self)
        try await EvalRunner.run(task: .planReview, dataset: "plan_review/v1", cases: cases,
                                 caseID: { $0.id }) { item in
            await Self.planReviewAttempt(item)
        }
    }

    func testPlanResearch() async throws {
        try EvalEnv.requireLive()
        let cases = try EvalDataset.load("plan_build/v1.jsonl", as: PlanBuildCase.self)
        try await EvalRunner.run(task: .planResearch, dataset: "plan_build/v1", cases: cases,
                                 caseID: { $0.id }) { item in
            await Self.planResearchAttempt(item)
        }
    }

    // MARK: - planBuild

    @MainActor
    static func planBuildAttempt(_ item: PlanBuildCase) async -> EvalOutcome {
        if let problem = item.problem {
            return EvalOutcome(ok: false, error: "dataset: \(item.id): \(problem)", scores: [:], pass: false, output: "")
        }
        let inputs = planInputs(item)
        let profile = inputs.profile
        // What `generate` computes before its two phases, from the same functions.
        let dataSummary = CoachContext.summary(profile: profile, foods: inputs.foods, weights: inputs.weights,
                                               water: inputs.water, sessions: inputs.sessions, exercises: [])
        let points = PlanService.loggedDayCount(foods: inputs.foods, weights: inputs.weights)
        let coaching = PlanService.coachingNote(profile: profile, foods: inputs.foods, weights: inputs.weights)
        // The research phase is skipped: the build is measured on the person's data and words
        // alone, which is also what the app sends when research returns nothing.
        let grounding = ""
        let system = PlanService.systemPrompt(profile: profile)
        let userContent = PlanService.userContent(dataSummary: dataSummary, intake: item.intake,
                                                  about: profile.onboardingNote) + coaching + grounding
        let facts = planFacts(inputs, reader: item.reader)

        let tap = await EvalRunner.recording { () async throws -> [String: Any] in
            let client = try AIClient.makeFull()
            return try await client.structured(
                system: system, userContent: userContent,
                toolName: PlanBuildCall.toolName, toolDescription: PlanBuildCall.toolDescription,
                schema: PlanService.planSchema, model: AIConfig.model(for: .planBuild),
                maxTokens: PlanBuildCall.maxTokens)
        }
        switch tap.result {
        case .failure(let error):
            // A failed call or a reply the client could not decode: the intake sheet shows its error.
            var outcome = EvalOutcome.failed(error, output: tap.raw ?? "")
            outcome.given = userContent
            return outcome
        case .success(let result):
            let plan = PlanService.makePlan(from: result, dataPoints: points)
            let graded = Graders.adaptivePlan(plan, raw: result, given: userContent, facts: facts)
            return EvalOutcome(ok: true, error: nil, scores: graded.scores, pass: graded.pass,
                               output: String((tap.raw ?? EvalRunner.compactJSON(result)).prefix(EvalRunner.outputLimit)),
                               shown: String(planShown(plan).prefix(EvalRunner.givenLimit)),
                               given: userContent)
        }
    }

    // MARK: - planReview

    @MainActor
    static func planReviewAttempt(_ item: PlanReviewCase) async -> EvalOutcome {
        if let problem = item.problem {
            return EvalOutcome(ok: false, error: "dataset: \(item.id): \(problem)", scores: [:], pass: false, output: "")
        }
        let inputs = planInputs(item)
        let profile = inputs.profile
        let existing = item.coachPlan(now: .now)

        // The targets the app mirrors from the plan in force (`PlanTargetSync.apply` without its
        // UserDefaults anchors: a plan with no direction record drives the current direction).
        let mirrored = PlanTargetSync.overrides(
            plan: PlanTargetSync.PlanTargets(hasRange: existing.hasRange, calorieMin: existing.calorieMin,
                                             calorieMax: existing.calorieMax, proteinTarget: existing.proteinTarget),
            currentProtein: profile.proteinTargetOverride, direction: profile.pace.direction)
        profile.calorieTargetOverride = mirrored.calorie
        profile.calorieMaxOverride = mirrored.calorieMax
        profile.proteinTargetOverride = mirrored.protein

        let before = Graders.PlanBefore(calorieMin: existing.calorieMin, calorieMax: existing.calorieMax,
                                        proteinTarget: existing.proteinTarget)
        let facts = planFacts(inputs, reader: item.reader)
        // The user turn `review` will build, rebuilt from the same pure functions BEFORE the call
        // (the call mutates the plan and the profile), for the numbers score only. The record's
        // `given` is left to the harness, which reads the turn from the request actually sent.
        let summary = CoachContext.summary(profile: profile, foods: inputs.foods, weights: inputs.weights,
                                           water: inputs.water, sessions: inputs.sessions, exercises: [])
        let rebuiltTurn = PlanService.reviewUserContent(plan: existing, dataSummary: summary,
                                                        daysSince: PlanService.daysSince(existing.updatedAt),
                                                        about: profile.onboardingNote)
            + PlanService.coachingNote(profile: profile, foods: inputs.foods, weights: inputs.weights)

        let container: ModelContainer
        do { container = try TestStore.makeContainer() } catch { return .failed(error) }
        let context = container.mainContext
        context.insert(profile)
        inputs.foods.forEach(context.insert)
        inputs.weights.forEach(context.insert)
        inputs.water.forEach(context.insert)
        inputs.sessions.forEach(context.insert)
        context.insert(existing)
        do { try context.save() } catch { return .failed(error) }

        let tap = await EvalRunner.recording {
            try await PlanService.review(profile: profile, foods: inputs.foods, weights: inputs.weights, context: context)
        }
        withExtendedLifetime(container) {}
        switch tap.result {
        case .failure(let error):
            // The Progress card shows its review error and keeps the old plan.
            return .failed(error, output: tap.raw ?? "")
        case .success(let plan):
            let raw = EvalRunner.jsonObject(tap.raw)
            let graded = Graders.adaptivePlan(plan, raw: raw, given: rebuiltTurn, facts: facts,
                                              before: before, expectRange: item.expectRange)
            return EvalOutcome(ok: true, error: nil, scores: graded.scores, pass: graded.pass,
                               output: String((tap.raw ?? "").prefix(EvalRunner.outputLimit)),
                               shown: String(planShown(plan).prefix(EvalRunner.givenLimit)))
        }
    }

    // MARK: - planResearch

    @MainActor
    static func planResearchAttempt(_ item: PlanBuildCase) async -> EvalOutcome {
        if let problem = item.problem {
            return EvalOutcome(ok: false, error: "dataset: \(item.id): \(problem)", scores: [:], pass: false, output: "")
        }
        let profile = planInputs(item).profile
        let system = PlanService.researchSystemPrompt(profile: profile)
        let user = PlanService.researchUserContent(profile: profile, intake: item.intake)

        // `researchGrounding`'s provider switch, without its cache lookup and store.
        let call = await planResponses { () async throws -> (text: String, usedSearch: Bool) in
            switch AIConfig.provider {
            case .anthropic:
                return try await AnthropicClient().research(system: system, userContent: user,
                                                            model: AIConfig.model(for: .planResearch))
            case .openai:
                return try await OpenAIClient().research(system: system, userContent: user,
                                                         model: AIConfig.model(for: .planResearch))
            }
        }
        let usage = researchUsage(call.responses)
        switch call.result {
        case .failure(let error):
            // `researchGrounding` swallows this (`try?`) and the build goes ahead un-grounded.
            var outcome = EvalOutcome.failed(error)
            outcome.scores = ["used": 0, "web_search_requests": Double(usage.searches),
                              "web_search_usd": Double(usage.searches) * researchUSDPerSearch]
            outcome.given = user
            return outcome
        case .success(let research):
            let brief = research.text
            let used = !brief.isEmpty   // the app folds in any non-empty brief (and caches it only if it searched)
            let scores: [String: Double] = [
                "used": used ? 1 : 0,
                "searched": research.usedSearch ? 1 : 0,
                "web_search_requests": Double(usage.searches),
                "web_search_usd": Double(usage.searches) * researchUSDPerSearch,
                "cited_sources": Double(usage.sources),
                "brief_words": Double(Graders.wordCount(brief)),
                "brief_chars": Double(brief.count),
                "mentions_protein": Graders.mentions(brief, "protein") ? 1 : 0,
                "mentions_a_rate": brief.range(of: #"(?i)(per week|a week|/\s?w(ee)?k|weekly)"#,
                                               options: .regularExpression) != nil ? 1 : 0,
                "wrong_person_pronoun": Graders.wrongPersonPronoun(brief, reader: item.reader) ? 1 : 0,
            ]
            // PASS = the app would use the brief AND it is grounded in a live search (the phase's
            // whole purpose, and the only brief the app caches).
            let pass = used && research.usedSearch
            return EvalOutcome(ok: used, error: used ? nil : "the brief was empty", scores: scores, pass: pass,
                               output: String(brief.prefix(EvalRunner.outputLimit)),
                               // The full brief for the judge (`output` is cut at 4,000 characters).
                               shown: used ? String(brief.prefix(EvalRunner.givenLimit)) : nil,
                               given: user)
        }
    }

    /// Anthropic and OpenAI both price web search at $10 per 1,000 searches.
    static let researchUSDPerSearch = 0.01

    /// Runs `body` with every provider response kept, in order (the harness's own recorder keeps
    /// only the last reply's text), so the record can say how many searches the reply used.
    static func planResponses<T>(isolation: isolated (any Actor)? = #isolation,
                                 _ body: () async throws -> T) async -> (result: Result<T, Error>, responses: [Data]) {
        let log = ConversationResponseLog(around: AIRuntime.transport)
        var runtime = AIRuntime.current ?? AIRuntime()
        runtime.transport = log
        let result: Result<T, Error>
        do {
            result = .success(try await AIRuntime.$current.withValue(runtime) { try await body() })
        } catch {
            result = .failure(error)
        }
        return (result, log.responses)
    }

    /// Searches run and distinct sources cited, read from the last completed research response.
    /// Anthropic: `usage.server_tool_use.web_search_requests` (else the `server_tool_use` blocks),
    /// and the `url` of every text block's `citations`. OpenAI Responses: completed
    /// `web_search_call` items, and the `url_citation` annotations of the reply's text.
    static func researchUsage(_ responses: [Data]) -> (searches: Int, sources: Int) {
        for data in responses.reversed() {
            guard let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                  json["error"] == nil || json["error"] is NSNull else { continue }
            if let content = json["content"] as? [[String: Any]] {
                let reported = ((json["usage"] as? [String: Any])?["server_tool_use"] as? [String: Any])?["web_search_requests"] as? Int
                let blocks = content.filter { ($0["type"] as? String) == "server_tool_use" }.count
                let urls = content.flatMap { ($0["citations"] as? [[String: Any]]) ?? [] }.compactMap { $0["url"] as? String }
                return (reported ?? blocks, Set(urls).count)
            }
            if let output = json["output"] as? [[String: Any]] {
                let calls = output.filter {
                    ($0["type"] as? String) == "web_search_call" && ($0["status"] as? String) == "completed"
                }.count
                let urls = output.filter { ($0["type"] as? String) == "message" }
                    .flatMap { ($0["content"] as? [[String: Any]]) ?? [] }
                    .flatMap { ($0["annotations"] as? [[String: Any]]) ?? [] }
                    .filter { ($0["type"] as? String) == "url_citation" }
                    .compactMap { $0["url"] as? String }
                return (calls, Set(urls).count)
            }
        }
        return (0, 0)
    }

    // MARK: - Shared: the person, the logs, the facts a grader needs, what Progress shows

    /// The case's person and logs as app objects: a fixture user (Alex or Sam) with the case's
    /// goal and profile changes and About You, and either the fixture's own logs (no `log`) or
    /// the logs the case describes. Water is always the fixture's (one bottle today).
    @MainActor
    static func planInputs(_ person: some PlanEvalPerson, now: Date = .now) -> PlanEvalInputs {
        let fixture = EvalFixtures.user(person.fixtureKey ?? "loss")
        let profile = fixture.profile
        if let pace = person.pace, let chosen = GoalPace(rawValue: pace) { profile.pace = chosen }
        if let goal = person.goalWeight { profile.goalWeightLbs = goal }
        if let start = person.startWeight { profile.startWeightLbs = start }
        if let activity = person.activity, let level = ActivityLevel(rawValue: activity) { profile.activityLevel = level }
        profile.onboardingNote = person.bio ?? ""
        guard let log = person.log else {
            return PlanEvalInputs(profile: profile, foods: fixture.foods, weights: fixture.weights,
                                  water: fixture.water, sessions: [])
        }

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        func day(_ daysAgo: Int) -> Date { calendar.date(byAdding: .day, value: -daysAgo, to: today) ?? today }
        func at(_ daysAgo: Int, _ hour: Int) -> Date {
            calendar.date(bySettingHour: hour, minute: 15, second: 0, of: day(daysAgo)) ?? day(daysAgo)
        }

        // Weigh-ins: one every `every` days from `endDaysAgo` back across `days` days, on a
        // straight line from `start` (the oldest end of the span) to `end` (the newest), with an
        // alternating ±wobble/2 so the scale looks like a scale. At midnight, like the fixture,
        // so none is ever in the future.
        var weights: [WeightEntry] = []
        if let w = log.weighIns {
            let span = max(1, w.days)
            for (index, offset) in stride(from: 0, to: span, by: max(1, w.every ?? 1)).enumerated() {
                let fraction = span > 1 ? Double(offset) / Double(span - 1) : 0
                var lbs = w.end + (w.start - w.end) * fraction
                if let wobble = w.wobble { lbs += (index.isMultiple(of: 2) ? 0.5 : -0.5) * wobble }
                weights.append(WeightEntry(date: day((w.endDaysAgo ?? 0) + offset), weightLbs: (lbs * 10).rounded() / 10))
            }
        }

        // Food: each logged day takes the next total from `kcal` / `protein` (cycled; the
        // `weekend` lists instead on a Friday or Saturday), split over `perDay` meals named in
        // turn from `meals`. `skip` holds days-ago values with nothing logged.
        var foods: [FoodEntry] = []
        if let f = log.food, !f.kcal.isEmpty, !f.protein.isEmpty, !f.meals.isEmpty {
            let skip = Set(f.skip ?? [])
            let perDay = max(1, min(f.perDay ?? 3, f.meals.count))
            let shares = planMealShares(perDay)
            let types: [MealType] = [.breakfast, .lunch, .dinner, .snack]
            let hours = [8, 12, 19, 15]
            var logged = 0
            for offset in 0..<max(0, f.days) {
                let daysAgo = (f.endDaysAgo ?? 0) + offset
                guard !skip.contains(daysAgo) else { continue }
                var kcal = f.kcal[logged % f.kcal.count]
                var protein = f.protein[logged % f.protein.count]
                let weekday = calendar.component(.weekday, from: day(daysAgo))   // 6 Friday, 7 Saturday
                if let weekend = f.weekend, !weekend.kcal.isEmpty, !weekend.protein.isEmpty, weekday == 6 || weekday == 7 {
                    kcal = weekend.kcal[logged % weekend.kcal.count]
                    protein = weekend.protein[logged % weekend.protein.count]
                }
                for slot in 0..<perDay {
                    let calories = (kcal * shares[slot]).rounded()
                    let proteinG = (protein * shares[slot]).rounded()
                    let rest = max(0, calories - proteinG * 4)
                    foods.append(FoodEntry(date: at(daysAgo, hours[min(slot, 3)]), mealType: types[min(slot, 3)],
                                           name: f.meals[(logged * perDay + slot) % f.meals.count],
                                           calories: calories, proteinG: proteinG,
                                           carbsG: (rest * 0.55 / 4).rounded(), fatG: (rest * 0.45 / 9).rounded()))
                }
                logged += 1
            }
        }

        let sessions = (log.sessions ?? []).map { session in
            WorkoutSession(date: at(session.daysAgo, 12), kind: WorkoutKind(rawValue: session.kind) ?? .other,
                           focuses: session.focuses.compactMap(MuscleFocus.init(rawValue:)),
                           durationMinutes: session.minutes, notes: session.notes)
        }
        return PlanEvalInputs(profile: profile, foods: foods, weights: weights, water: fixture.water, sessions: sessions)
    }

    /// How a day's total is split over its meals (breakfast, lunch, dinner, snack).
    static func planMealShares(_ count: Int) -> [Double] {
        switch count {
        case 1: return [1]
        case 2: return [0.45, 0.55]
        case 3: return [0.25, 0.35, 0.40]
        case 4: return [0.22, 0.30, 0.36, 0.12]
        default: return Array(repeating: 1 / Double(count), count: count)
        }
    }

    /// The app's own numbers for this person, from the profile helpers every target is built on.
    @MainActor
    static func planFacts(_ inputs: PlanEvalInputs, reader: Graders.Reader) -> Graders.PlanFacts {
        let profile = inputs.profile
        let weight = profile.basisWeightLbs(weights: inputs.weights)
        return Graders.PlanFacts(reader: reader, direction: profile.pace.direction,
                                 safeFloor: profile.safeCalorieFloor,
                                 maintenance: profile.tdee(weightLbs: weight),
                                 computedTarget: profile.calorieGoal(weightLbs: weight).dailyCalories,
                                 weightLbs: weight,
                                 loggedDays: PlanService.loggedDayCount(foods: inputs.foods, weights: inputs.weights))
    }

    /// What the Progress plan card and its sections show, in the card's own labels.
    @MainActor
    static func planShown(_ plan: CoachPlan, now: Date = .now) -> String {
        var lines = ["Headline: \(plan.headline)"]
        if plan.isEarlyRead { lines.append("[Early read — it'll sharpen as you log more]") }
        var targets: [String] = []
        if plan.hasRange { targets.append("Daily fuel: \(plan.calorieRangeText) kcal") }
        if plan.proteinTarget > 0 { targets.append("Protein: \(Int(plan.proteinTarget))g") }
        lines.append(targets.isEmpty ? "(no targets set)" : targets.joined(separator: " · "))
        lines.append("\nAssessment:\n\(plan.assessment)")
        lines.append("\nStrategy:\n\(plan.strategy)")
        lines.append("\nInsights:")
        lines += plan.insights.map { "- [\($0.tone.rawValue)] \($0.title): \($0.body)" }
        lines.append("\nChangelog:")
        lines += plan.changelog.map { change in
            let days = PlanService.daysSince(change.date, now: now)
            return "- \(days == 0 ? "today" : "\(days) day\(days == 1 ? "" : "s") ago"): \(change.summary)"
        }
        return lines.joined(separator: "\n")
    }
}

// MARK: - The shape both plan datasets share

/// What a plan case says about the person. `user` is `alex` (the fixture man, gaining) or
/// `sam` (the fixture woman, losing); the optional fields change that fixture's profile.
protocol PlanEvalPerson {
    var id: String { get }
    var user: String { get }
    /// A `GoalPace` raw value (`maintain`, `steady`, ...), absent for the fixture's own.
    var pace: String? { get }
    var goalWeight: Double? { get }
    var startWeight: Double? { get }
    /// An `ActivityLevel` raw value, absent for the fixture's `light`.
    var activity: String? { get }
    /// Their About You (`UserProfile.onboardingNote`); absent for none.
    var bio: String? { get }
    /// The logs; absent for the fixture's own (one day of food, ten weigh-ins, one bottle of water).
    var log: PlanEvalLog? { get }
}

extension PlanEvalPerson {
    /// The key `EvalFixtures` takes: `gain` is Alex, anything else is Sam.
    var fixtureKey: String? {
        switch user {
        case "alex": return "gain"
        case "sam": return "loss"
        default: return nil
        }
    }

    var reader: Graders.Reader { EvalFixtures.reader(fixtureKey ?? "loss") }

    /// Why the person part of a case cannot be built as the app would hold it, or nil.
    var personProblem: String? {
        if fixtureKey == nil { return "user \(user) is neither alex nor sam" }
        if let pace = self.pace, GoalPace(rawValue: pace) == nil { return "pace \(pace) is not a GoalPace" }
        if let activity = self.activity, ActivityLevel(rawValue: activity) == nil {
            return "activity \(activity) is not an ActivityLevel"
        }
        guard let log = self.log else { return nil }
        if let w = log.weighIns, w.days < 1 || (w.every ?? 1) < 1 || (w.endDaysAgo ?? 0) < 0 || w.start <= 0 || w.end <= 0 {
            return "weighIns needs days >= 1, every >= 1, endDaysAgo >= 0 and positive weights"
        }
        if let f = log.food {
            if f.days < 1 || f.kcal.isEmpty || f.protein.isEmpty || f.meals.isEmpty
                || (f.perDay ?? 3) < 1 || (f.endDaysAgo ?? 0) < 0 {
                return "food needs days >= 1, kcal, protein and meals, perDay >= 1, endDaysAgo >= 0"
            }
            if let weekend = f.weekend, weekend.kcal.isEmpty || weekend.protein.isEmpty {
                return "food.weekend needs kcal and protein"
            }
        }
        for session in log.sessions ?? [] {
            if session.daysAgo < 0 || WorkoutKind(rawValue: session.kind) == nil
                || !session.focuses.allSatisfy({ MuscleFocus(rawValue: $0) != nil }) {
                return "session \(session.kind) \(session.focuses) on day -\(session.daysAgo) is not the app's"
            }
        }
        return nil
    }
}

/// A case's logs, written compactly (see `LiveEvals.planInputs` for how each becomes rows).
struct PlanEvalLog: Decodable, Sendable {
    struct WeighIns: Decodable, Sendable {
        let days: Int
        let every: Int?
        let endDaysAgo: Int?
        let start: Double
        let end: Double
        let wobble: Double?
    }
    struct Food: Decodable, Sendable {
        struct Weekend: Decodable, Sendable {
            let kcal: [Double]
            let protein: [Double]
        }
        let days: Int
        let endDaysAgo: Int?
        let skip: [Int]?
        let kcal: [Double]
        let protein: [Double]
        let meals: [String]
        let perDay: Int?
        let weekend: Weekend?
    }
    let weighIns: WeighIns?
    let food: Food?
    let sessions: [LiveEvals.CoachDataCase.Session]?
}

struct PlanEvalInputs {
    let profile: UserProfile
    let foods: [FoodEntry]
    let weights: [WeightEntry]
    let water: [WaterEntry]
    let sessions: [WorkoutSession]
}

// MARK: - The grader for a written or reviewed plan

extension Graders {

    /// The app's own numbers for the person a plan is for.
    struct PlanFacts {
        let reader: Reader
        let direction: GoalPace.Direction
        /// `UserProfile.safeCalorieFloor` (1,200 women / 1,500 men): the target is clamped to it at
        /// read time, so a plan below it shows a range on Progress that the app does not follow.
        let safeFloor: Double
        /// `UserProfile.tdee` at the basis weight (Mifflin-St Jeor x the profile's activity level).
        let maintenance: Double
        /// `UserProfile.calorieGoal`: the target the app computes with no plan.
        let computedTarget: Double
        let weightLbs: Double
        let loggedDays: Int
    }

    /// The reviewed plan's numbers before the review.
    struct PlanBefore {
        let calorieMin: Double
        let calorieMax: Double
        let proteinTarget: Double
    }

    /// Grades the plan the app would store (`PlanService.makePlan` of the reply, or what `review`
    /// left in the store), with `raw` the reply as the model wrote it.
    ///
    /// PASS = the plan is one the app can stand behind:
    /// - it decoded with a headline, an assessment and a strategy;
    /// - a calorie range is set (`hasRange`: floor above 0, ceiling at or above it, after the
    ///   app's own swap of a reversed pair);
    /// - the floor is at or above the app's safe floor (the target is clamped there at read
    ///   time; a plan under it is a range on Progress the app does not follow, and breaks the
    ///   prompt's "a floor that prevents under-eating");
    /// - a protein target is set;
    /// - 3 to 5 insights (the prompt's hard rule, as `checklistPlan` holds its bounds);
    /// - no wrong-person pronoun in the prose or the About You.
    /// Recorded, not required: the range's direction against maintenance (the profile's activity
    /// level can understate a runner or a nurse, so a sound plan may sit "wrong" of it), protein
    /// per pound, the insight tones as written, prose lengths, hedging on an early read, numbers
    /// not in the input, and for a review how the numbers moved.
    static func adaptivePlan(_ plan: CoachPlan, raw: [String: Any]?, given: String, facts: PlanFacts,
                             before: PlanBefore? = nil, expectRange: String? = nil)
        -> (scores: [String: Double], pass: Bool) {
        func flag(_ condition: Bool) -> Double { condition ? 1 : 0 }

        let prosePresent = [plan.headline, plan.assessment, plan.strategy]
            .allSatisfy { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        let aboveFloor = plan.hasRange && plan.calorieMin >= facts.safeFloor
        let proteinSet = plan.proteinTarget > 0
        let insightsInBounds = (3...5).contains(plan.insights.count)

        let note = plan.changelog.last?.summary ?? ""
        let prose = ([plan.headline, plan.assessment, plan.strategy]
                     + plan.insights.flatMap { [$0.title, $0.body] } + [note]).joined(separator: "\n")
        let aboutYou = (raw?["about_you"] as? String) ?? ""
        let wrongPerson = wrongPersonPronoun(prose + "\n" + aboutYou, reader: facts.reader)

        // The plan's own targets are figures it is asked to set, so they count as given.
        let own = [plan.calorieMin, plan.calorieMax, plan.proteinTarget].filter { $0 > 0 }
            .map { String(Int($0.rounded())) }.joined(separator: " ")
        let givenPlus = given + "\n" + own
        let outside = numbersNotGiven(in: prose, given: givenPlus)
        let derived = derivedFigures(outside, given: Set(numbers(in: givenPlus)))

        let rawInsights = (raw?["insights"] as? [[String: Any]]) ?? []
        let rawTones = rawInsights.map { ($0["tone"] as? String) ?? "" }
        let rawMin = planNumber(raw?["calorie_min"]), rawMax = planNumber(raw?["calorie_max"])
        let rawNote = ((raw?["changelog_note"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

        var scores: [String: Double] = [
            "used": 1,
            "prose_present": flag(prosePresent),
            "has_range": flag(plan.hasRange),
            "calorie_min_at_or_above_floor": flag(aboveFloor),
            "protein_set": flag(proteinSet),
            "insight_count": Double(plan.insights.count),
            "insights_three_to_five": flag(insightsInBounds),
            "wrong_person_pronoun": flag(wrongPerson),
            "insight_tones_valid_as_written": flag(!rawTones.isEmpty
                                                   && rawTones.allSatisfy { PlanInsight.Tone(rawValue: $0) != nil }),
            "range_ordered_as_written": flag(rawMin != nil && rawMax != nil && rawMin! <= rawMax!),
            "changelog_note_written": flag(!rawNote.isEmpty),
            "about_you_written": flag(!aboutYou.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty),
            "no_number_outside_the_input": flag(outside.isEmpty),
            "numbers_outside_the_input": Double(outside.count),
            "numbers_outside_that_are_sums_or_differences": Double(derived.count),
            "assessment_words": Double(wordCount(plan.assessment)),
            "strategy_words": Double(wordCount(plan.strategy)),
            "logged_days": Double(facts.loggedDays),
        ]
        if plan.hasRange {
            let mid = (plan.calorieMin + plan.calorieMax) / 2
            let fits: Bool
            switch facts.direction {
            case .lose: fits = mid < facts.maintenance
            case .gain: fits = mid > facts.maintenance
            case .maintain: fits = abs(mid - facts.maintenance) <= 0.10 * facts.maintenance
            }
            scores["range_direction_fits_goal"] = flag(fits)
            scores["range_mid_minus_maintenance_kcal"] = (mid - facts.maintenance).rounded()
            scores["range_width_kcal"] = plan.calorieMax - plan.calorieMin
            scores["range_contains_app_target"] = flag((plan.calorieMin...plan.calorieMax).contains(facts.computedTarget))
        }
        if proteinSet, facts.weightLbs > 0 {
            let perLb = plan.proteinTarget / facts.weightLbs
            scores["protein_g_per_lb"] = (perLb * 100).rounded() / 100
            // 0.6-1.2 g/lb is about 1.3-2.6 g/kg: wide around the 1.6-2.2 g/kg usually advised
            // for people who train, so only a clearly odd target falls outside it.
            scores["protein_in_sane_band"] = flag((0.6...1.2).contains(perLb))
        }
        if facts.loggedDays < 7 {
            let hedges = ["early", "sharpen", "more data", "more days", "as more", "few days", "first read",
                          "first look", "so far", "only one", "a few logged"]
            scores["hedges_on_an_early_read"] = flag(hedges.contains { containsPhrase(prose, $0) })
        }
        if let before = before {
            let dMin = plan.calorieMin - before.calorieMin
            let dMax = plan.calorieMax - before.calorieMax
            let dProtein = plan.proteinTarget - before.proteinTarget
            let dMid = (dMin + dMax) / 2
            scores["calorie_min_change_kcal"] = dMin
            scores["calorie_max_change_kcal"] = dMax
            scores["protein_change_g"] = dProtein
            let saysNoChange = containsPhrase(note, "No change needed")
            scores["says_no_change"] = flag(saysNoChange)
            if saysNoChange {
                scores["no_change_note_matches_the_numbers"] = flag(abs(dMin) < 1 && abs(dMax) < 1 && abs(dProtein) < 1)
            }
            if let expectRange = expectRange {
                let moved: Bool
                switch expectRange {
                case "hold": moved = abs(dMid) <= 50
                case "raise": moved = dMid > 50
                case "lower": moved = dMid < -50
                case "notRaise": moved = dMid <= 50
                case "notLower": moved = dMid >= -50
                default: moved = false
                }
                scores["range_moved_as_expected"] = flag(moved)
            }
        }
        let pass = prosePresent && plan.hasRange && aboveFloor && proteinSet && insightsInBounds && !wrongPerson
        return (scores, pass)
    }

    /// A number as the model wrote it (JSON number or numeric string), for the raw-reply scores.
    static func planNumber(_ value: Any?) -> Double? {
        if let number = value as? NSNumber { return number.doubleValue }
        if let text = value as? String { return Double(text.trimmingCharacters(in: .whitespaces)) }
        return nil
    }
}

// MARK: - Offline checks (no network, no key): the datasets and the copied literals

/// Its own class so `LiveEvals` keeps exactly the live tests `Evals/run.sh` names.
@MainActor
final class PlanEvalDatasetChecks: XCTestCase {

    private var repoRoot: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    }

    private func rows<T: Decodable>(_ path: String, as type: T.Type) throws -> [T] {
        try EvalDataset.decode(contentsOf: repoRoot.appendingPathComponent("Evals/datasets/\(path)"), as: type)
    }

    func testPlanDatasetsAreWellFormed() throws {
        let builds = try rows("plan_build/v1.jsonl", as: LiveEvals.PlanBuildCase.self)
        let reviews = try rows("plan_review/v1.jsonl", as: LiveEvals.PlanReviewCase.self)
        XCTAssertGreaterThanOrEqual(builds.count, 12)
        XCTAssertGreaterThanOrEqual(reviews.count, 12)
        XCTAssertEqual(Set(builds.map(\.id)).count, builds.count, "plan_build ids must be unique")
        XCTAssertEqual(Set(reviews.map(\.id)).count, reviews.count, "plan_review ids must be unique")
        for item in builds { XCTAssertNil(item.problem, item.id) }
        for item in reviews { XCTAssertNil(item.problem, item.id) }
        for users in [Set(builds.map(\.user)), Set(reviews.map(\.user))] { XCTAssertEqual(users, ["alex", "sam"]) }
        XCTAssertTrue(builds.contains { $0.pace == "maintain" } && reviews.contains { $0.pace == "maintain" })

        // The situations the cases claim are the ones the app's own code sees.
        let lowIntake = try XCTUnwrap(builds.first { $0.id == "build-sam-very-low-intake" })
        let low = LiveEvals.planInputs(lowIntake)
        XCTAssertFalse(PlanService.coachingFlags(profile: low.profile, foods: low.foods, weights: low.weights).isEmpty,
                       "the very-low-intake case must trip the plan's eat-more teaching moment")
        let belowFloor = try XCTUnwrap(reviews.first { $0.id == "review-sam-plan-below-floor" })
        XCTAssertLessThan(belowFloor.plan.calorieMin, LiveEvals.planInputs(belowFloor).profile.safeCalorieFloor)
        let firstDay = try XCTUnwrap(builds.first { $0.id == "build-sam-first-day-no-logs" })
        let fresh = LiveEvals.planInputs(firstDay)
        XCTAssertEqual(PlanService.loggedDayCount(foods: fresh.foods, weights: fresh.weights), 1)
        let comeback = try XCTUnwrap(reviews.first { $0.id == "review-alex-comeback-after-gap" })
        let back = LiveEvals.planInputs(comeback)
        XCTAssertTrue(CoachContext.summary(profile: back.profile, foods: back.foods, weights: back.weights,
                                           water: back.water).contains("coming back after"))
        let weekend = try XCTUnwrap(builds.first { $0.id == "build-sam-weekend-pattern" })
        let byDay = Dictionary(grouping: LiveEvals.planInputs(weekend).foods) { Calendar.current.startOfDay(for: $0.date) }
            .mapValues { $0.reduce(0) { $0 + $1.calories } }
        for (day, total) in byDay {
            let weekday = Calendar.current.component(.weekday, from: day)
            XCTAssertEqual(total > 2_400, weekday == 6 || weekday == 7, "weekend days are the big ones")
        }
        // Every intake carries the three labels the sheet writes, empty boxes included.
        for item in builds {
            XCTAssertTrue(item.intake.hasPrefix("Timeframe: ") && item.intake.contains("\nDay-to-day: ")
                          && item.intake.contains("\nExercise & schedule: "), item.id)
        }
    }

    /// The literals `LiveEvals.planBuildAttempt` repeats from code that does not expose them.
    func testPlanBuildRepeatsTheAppsOwnCall() throws {
        let service = try String(contentsOf: repoRoot.appendingPathComponent("Sprout/Services/PlanService.swift"),
                                 encoding: .utf8)
        let generate = try XCTUnwrap(service.components(separatedBy: "static func generate(").dropFirst().first?
            .components(separatedBy: "static func review(").first)
        for line in [
            "let research = await researchGrounding(profile: profile, intake: intake)",
            "system: systemPrompt(profile: profile),",
            "userContent: userContent(dataSummary: dataSummary, intake: intake, about: profile.onboardingNote) + coaching + research.grounding,",
            "toolName: \"\(LiveEvals.PlanBuildCall.toolName)\",",
            "toolDescription: \"\(LiveEvals.PlanBuildCall.toolDescription)\",",
            "schema: planSchema,",
            "model: AIConfig.model(for: .planBuild),",
            "maxTokens: \(LiveEvals.PlanBuildCall.maxTokens)",
            "let coaching = coachingNote(profile: profile, foods: foods, weights: weights)",
            "let points = loggedDayCount(foods: foods, weights: weights)",
        ] {
            XCTAssertTrue(generate.contains(line), "PlanService.generate no longer has: \(line)")
        }
        for line in [
            "research = try? await AnthropicClient().research(system: system, userContent: user,",
            "research = try? await OpenAIClient().research(system: system, userContent: user,",
            "model: AIConfig.model(for: .planResearch))",
        ] {
            XCTAssertTrue(service.contains(line), "PlanService.researchGrounding no longer has: \(line)")
        }
        let intake = try String(contentsOf: repoRoot.appendingPathComponent("Sprout/Features/Plan/PlanIntakeView.swift"),
                                encoding: .utf8)
        for line in [
            "Timeframe: \\(timeframe.trimmingCharacters(in: .whitespacesAndNewlines))",
            "Day-to-day: \\(dayToDay.trimmingCharacters(in: .whitespacesAndNewlines))",
            "Exercise & schedule: \\(exercise.trimmingCharacters(in: .whitespacesAndNewlines))",
        ] {
            XCTAssertTrue(intake.contains(line), "PlanIntakeView.build() no longer writes: \(line)")
        }
    }

    func testPlanGraderOnHandWrittenPlans() {
        let sam = EvalFixtures.reader("loss")
        let facts = Graders.PlanFacts(reader: sam, direction: .lose, safeFloor: 1200, maintenance: 2000,
                                      computedTarget: 1750, weightLbs: 158, loggedDays: 10)
        func reply(min: Double, max: Double, insights: Int = 3, prose: String = "Your trend is moving down.") -> [String: Any] {
            [
                "headline": "Steady toward 145", "assessment": prose, "strategy": "- Land in the range most days.",
                "calorie_min": min, "calorie_max": max, "protein_target": 110,
                "insights": (0..<insights).map { index -> [String: Any] in
                    ["title": "Insight \(index)", "body": "Keep going.", "tone": "win"]
                },
                "changelog_note": "Plan created.", "about_you": "Works a desk job; walks the dog daily.",
            ]
        }
        func grade(_ raw: [String: Any]) -> (scores: [String: Double], pass: Bool) {
            Graders.adaptivePlan(PlanService.makePlan(from: raw, dataPoints: 10), raw: raw, given: "", facts: facts)
        }

        let sound = grade(reply(min: 1500, max: 1650))
        XCTAssertTrue(sound.pass)
        XCTAssertEqual(sound.scores["range_direction_fits_goal"], 1)
        XCTAssertEqual(sound.scores["range_ordered_as_written"], 1)

        let underFloor = grade(reply(min: 1000, max: 1150))
        XCTAssertFalse(underFloor.pass)
        XCTAssertEqual(underFloor.scores["calorie_min_at_or_above_floor"], 0)

        let reversed = grade(reply(min: 1650, max: 1500))     // the app swaps it, so it still passes
        XCTAssertTrue(reversed.pass)
        XCTAssertEqual(reversed.scores["range_ordered_as_written"], 0)

        XCTAssertFalse(grade(reply(min: 1500, max: 1650, insights: 2)).pass)
        XCTAssertFalse(grade(reply(min: 1500, max: 1650, prose: "He is doing well.")).pass)   // Sam is a woman
        XCTAssertEqual(grade(reply(min: 2100, max: 2300)).scores["range_direction_fits_goal"], 0)
    }
}
