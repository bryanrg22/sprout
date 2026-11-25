import Foundation
import UIKit
import XCTest
@testable import Sprout

/// Live evaluations: each runs the app's own code path for one task against every
/// configured candidate model. Skipped unless `Evals/run.sh` configured a run.
final class LiveEvals: XCTestCase {

    // MARK: - mealDescribe: typed meal → structured estimate, graded against USDA totals

    func testMealDescribe() async throws {
        try EvalEnv.requireLive()
        // v3 = v1's cases plus the label nutrients of the same USDA records; the pass rule is
        // still calories within 20%, and the four estimated nutrients are scored beside it.
        // Built on 2026-11-25 from the fetched USDA detail (`fetch_usda.py --details-only`,
        // then `build_v3.py`); CI rebuilds it and diffs, as it does v1.
        let cases = try EvalDataset.load("meal_describe/v3.jsonl", as: Graders.MealTruth.self)
        try await EvalRunner.run(task: .mealDescribe, dataset: "meal_describe/v3", cases: cases,
                                 caseID: { $0.id }) { truth in
            do {
                let estimate = try await FoodPhotoAnalyzer.analyze(description: truth.description)
                let graded = Graders.meal(estimate, truth: truth)
                let output = (try? JSONEncoder().encode(estimate)).map { String(decoding: $0, as: UTF8.self) } ?? ""
                return EvalOutcome(ok: true, error: nil, scores: graded.scores, pass: graded.pass, output: output)
            } catch {
                return .failed(error)
            }
        }
    }

    // MARK: - coachTurn: first turn of a chat → the right tool, with the right arguments, or prose

    func testCoachToolChoice() async throws {
        try EvalEnv.requireLive()
        let cases = try EvalDataset.load("coach_tool_choice/v2.jsonl", as: Graders.ToolExpectation.self)
        try await EvalRunner.run(task: .coachTurn, dataset: "coach_tool_choice/v2", cases: cases,
                                 caseID: { $0.id }) { expectation in
            await Self.coachAttempt(expectation)
        }
    }

    @MainActor
    private static func coachAttempt(_ expectation: Graders.ToolExpectation) async -> EvalOutcome {
        let user = EvalFixtures.user(expectation.profile)
        // Exactly what CoachView.send builds for a first message.
        let parts = CoachContext.systemParts(profile: user.profile, foods: user.foods,
                                             weights: user.weights, water: user.water)
        let tools = CoachTools.schemas(for: user.profile)
        do {
            let turn = try await AIClient.makeFull().chatWithTools(
                system: parts.volatile,
                messages: [AnthropicClient.Msg(role: "user", content: expectation.utterance)],
                tools: tools,
                model: AIConfig.model(for: .coachTurn),
                maxTokens: 1500,
                cachedSystemPrefix: parts.stable,
                forbidToolUse: false)

            var called: Graders.ActionView?
            var invalid = false
            var output = turn.text
            if let toolUse = turn.toolUse {
                output = "\(toolUse.name) \(EvalRunner.compactJSON(toolUse.input))"
                switch CoachTools.parse(name: toolUse.name, input: toolUse.input,
                                        profile: user.profile, todaysFoods: user.foods) {
                case .ok(let request): called = Graders.ActionView(request.action)
                case .invalid(let reason): invalid = true; output += " → INVALID: \(reason)"
                }
            }
            let graded = Graders.toolChoice(expect: expectation, called: called, invalid: invalid)
            return EvalOutcome(ok: true, error: nil, scores: graded.scores, pass: graded.pass,
                               output: String(output.prefix(600)))
        } catch {
            return .failed(error)
        }
    }

    // MARK: - dailyBrief: rewarm the template the engine already chose, changing no fact

    struct BriefCase: Decodable, Sendable {
        let id: String
        let name: String
        /// Whether a feminine third-person pronoun about the reader would be wrong.
        let readerIsNotAWoman: Bool
        let daysAway: Int?
        let streak: Int?
        let sleepMinutes: Int?
        let deepMinutes: Int?
        let sleepAvgMinutes: Int?
        let restingHR: Double?
        let restingHRAvg: Double?
        let stepsYesterday: Int?
        let stepsAvg: Int?
        let workedOutYesterday: Bool?
        let trendEasedDown: Bool?
        let travelShiftHours: Int?
        let travelShiftDaysAgo: Int?
        /// The topic the template ladder must pick for these signals (a dataset self-check).
        let topic: String

        var signals: DailyBriefService.Signals {
            var s = DailyBriefService.Signals()
            s.name = name
            s.daysAway = daysAway
            s.streak = streak ?? 0
            s.sleepMinutes = sleepMinutes
            s.deepMinutes = deepMinutes
            s.sleepAvgMinutes = sleepAvgMinutes
            s.restingHR = restingHR
            s.restingHRAvg = restingHRAvg
            s.stepsYesterday = stepsYesterday
            s.stepsAvg = stepsAvg
            s.workedOutYesterday = workedOutYesterday ?? false
            s.trendEasedDown = trendEasedDown ?? false
            s.travelShiftHours = travelShiftHours
            s.travelShiftDaysAgo = travelShiftDaysAgo
            return s
        }
    }

    func testDailyBrief() async throws {
        try EvalEnv.requireLive()
        let cases = try EvalDataset.load("daily_brief/v1.jsonl", as: BriefCase.self)
        try await EvalRunner.run(task: .dailyBrief, dataset: "daily_brief/v1", cases: cases,
                                 caseID: { $0.id }) { item in
            let picked = DailyBriefService.pick(item.signals)
            guard picked.topic.rawValue == item.topic else {
                return EvalOutcome(ok: false, error: "dataset: ladder picked \(picked.topic.rawValue), case says \(item.topic)",
                                   scores: [:], pass: false, output: "")
            }
            // nil covers both a failed call and a reply the app's own guardrails rejected;
            // either way the user is shown the template, so both count as "not used".
            // A failed call and a reply the app's own guardrail discards both leave the user
            // with the template, so both count as "not used"; the record says which, and why.
            guard let raw = await DailyBriefService.rephraseRaw(picked, name: item.name) else {
                return EvalOutcome(ok: false, error: "the call failed", scores: ["used": 0], pass: false, output: "")
            }
            guard let reply = DailyBriefService.parse(raw) else {
                let reason = DailyBriefService.rejection(of: raw) ?? "rejected"
                return EvalOutcome(ok: false, error: "guardrail discarded the rewrite: \(reason)",
                                   scores: ["used": 0], pass: false, output: String(raw.prefix(500)))
            }
            let graded = Self.gradeBrief(template: (picked.headline, picked.body), reply: reply,
                                         readerIsNotAWoman: item.readerIsNotAWoman)
            return EvalOutcome(ok: true, error: nil, scores: graded.scores, pass: graded.pass,
                               output: "\(reply.headline)\n\(reply.body)")
        }
    }

    static func gradeBrief(template: (headline: String, body: String),
                           reply: (headline: String, body: String),
                           readerIsNotAWoman: Bool) -> (scores: [String: Double], pass: Bool) {
        let source = template.headline + " " + template.body
        let rewrite = reply.headline + " " + reply.body
        let kept = Graders.numbersPreserved(source: source, rewrite: rewrite)
        let wrongPerson = readerIsNotAWoman && Graders.containsFemininePronoun(rewrite)
        let scores: [String: Double] = [
            "used": 1,
            "all_numbers_kept": kept.allKept ? 1 : 0,
            "no_number_invented": kept.noneInvented ? 1 : 0,
            "headline_one_sentence": Graders.sentenceCount(reply.headline) <= 1 ? 1 : 0,
            "headline_at_most_one_number": Graders.numbers(in: reply.headline).count <= 1 ? 1 : 0,
            "body_at_most_two_sentences": Graders.sentenceCount(reply.body) <= 2 ? 1 : 0,
            "wrong_person_pronoun": wrongPerson ? 1 : 0,
            "changed_the_wording": rewrite != source ? 1 : 0,
        ]
        // Pass = safe to show: the facts are intact and it is about the right person.
        return (scores, kept.allKept && kept.noneInvented && !wrongPerson)
    }

    // MARK: - avatar: a photo → the person's pixel character (image generation, OpenAI only)

    /// One photo in `Evals/datasets/avatar/photos/`. Only synthetic or consented photos go
    /// there (see its README); none is checked in.
    struct AvatarCase: Sendable {
        let id: String
        let url: URL
    }

    static let avatarPhotoExtensions: Set<String> = ["jpg", "jpeg", "png", "heic", "webp"]

    /// The photos of a dataset folder, by file name. Pure listing, so it is tested offline.
    static func avatarCases(in folder: URL, limit: Int? = nil) -> [AvatarCase] {
        let names = ((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? [])
            .filter { avatarPhotoExtensions.contains(($0 as NSString).pathExtension.lowercased()) }
            .sorted()
        let cases = names.map { AvatarCase(id: ($0 as NSString).deletingPathExtension, url: folder.appendingPathComponent($0)) }
        return limit.map { Array(cases.prefix($0)) } ?? cases
    }

    /// `Evals/run.sh Avatar "openai:gpt-image-2.6-flare@low,openai:gpt-image-2.6-flare@medium,..." 3`
    ///
    /// The `@suffix` of a candidate is the image QUALITY here (`low`, `medium`, `high`, ...),
    /// not a reasoning effort; without one, `AIConfig.avatarImage.quality` is used. Runs
    /// `AvatarGenerator.generate`, the call the app makes, and grades the returned image in
    /// code. Each image is also saved under `<run>/avatars/` (git-ignored) so the owner can
    /// rate likeness and fit with the two existing characters, which no code here measures.
    func testAvatar() async throws {
        try EvalEnv.requireLive()
        guard let root = EvalEnv.root else { throw XCTSkip("SPROUT_EVAL_ROOT not set") }
        let cases = Self.avatarCases(in: root.appendingPathComponent("datasets/avatar/photos"), limit: EvalEnv.limit)
        guard !cases.isEmpty else {
            throw XCTSkip("no photos in Evals/datasets/avatar/photos (see its README)")
        }
        let out = EvalEnv.out
        try await EvalRunner.run(taskName: "avatar", dataset: "avatar/photos", cases: cases,
                                 caseID: { $0.id }) { item in
            guard let data = try? Data(contentsOf: item.url), let photo = UIImage(data: data) else {
                return EvalOutcome(ok: false, error: "dataset: \(item.url.lastPathComponent) is not a readable image",
                                   scores: [:], pass: false, output: "")
            }
            var setting = AIConfig.avatarImage
            if let quality = AIRuntime.current?.reasoningEffort { setting.quality = quality }
            do {
                let character = try await AvatarGenerator.generate(from: photo, setting: setting)
                return Self.avatarOutcome(character, caseID: item.id, out: out)
            } catch let failure as AvatarGenerator.Failure {
                // A refusal or a rejected image is a result, not a crash: it is what the
                // person would have hit, and the app would have shown a built-in character.
                return EvalOutcome(ok: false, error: String(describing: failure).prefix(300).description,
                                   scores: ["generator_accepted": 0], pass: false, output: "")
            } catch {
                return .failed(error)
            }
        }
    }

    /// Grades one generated character and saves it for the owner's own rating.
    static func avatarOutcome(_ character: AvatarGenerator.Character, caseID: String, out: URL?) -> EvalOutcome {
        let graded = Graders.avatar(character.png)
        var scores = graded.scores
        scores["generator_accepted"] = 1
        scores["generation_latency_ms"] = Double(character.latencyMs)
        if let usage = character.usage {
            scores["input_tokens"] = Double(usage.inputTokens)
            scores["input_text_tokens"] = Double(usage.inputTextTokens)
            scores["input_image_tokens"] = Double(usage.inputImageTokens)
            scores["output_tokens"] = Double(usage.outputTokens)
            if let cost = Graders.imageCostUSD(model: character.model, usage: usage) { scores["cost_usd"] = cost }
        }
        var saved = "not saved"
        if let out {
            let folder = out.appendingPathComponent("avatars/\(character.model)@\(character.quality)")
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let file = folder.appendingPathComponent("\(caseID)-\(UUID().uuidString.prefix(8)).png")
            if (try? character.png.write(to: file)) != nil { saved = "avatars/\(folder.lastPathComponent)/\(file.lastPathComponent)" }
        }
        return EvalOutcome(ok: true, error: nil, scores: scores, pass: graded.pass,
                           output: "\(character.model) \(character.quality) \(character.promptVersion) \(saved)")
    }

    /// One saved character graded again.
    struct RegradedAvatar: Equatable {
        let candidate: String
        let file: String
        let pass: Bool
        let scores: [String: Double]
    }

    /// Grades again the characters a past run saved under `<run>/avatars/`, with the graders
    /// as they are now, and writes the scores to `<run>/regrade-avatar.json` beside the
    /// grader settings that made them. The run's own records are left as they were written.
    @discardableResult
    static func regradeAvatars(in run: URL) throws -> [RegradedAvatar] {
        let files = FileManager.default
        let root = run.appendingPathComponent("avatars")
        let candidates = ((try? files.contentsOfDirectory(atPath: root.path)) ?? []).sorted()
        var images: [RegradedAvatar] = []
        for candidate in candidates {
            let folder = root.appendingPathComponent(candidate)
            let names = ((try? files.contentsOfDirectory(atPath: folder.path)) ?? [])
                .filter { $0.lowercased().hasSuffix(".png") }.sorted()
            for name in names {
                let graded = Graders.avatar((try? Data(contentsOf: folder.appendingPathComponent(name))) ?? Data())
                images.append(RegradedAvatar(candidate: candidate, file: name, pass: graded.pass, scores: graded.scores))
            }
        }
        guard !images.isEmpty else { return [] }
        let record: [String: Any] = [
            "graders": [
                "clear_alpha_ceiling": Int(Graders.clearAlphaCeiling),
                "solid_alpha_floor": Int(Graders.solidAlphaFloor),
                "colour_bits": Graders.colourBits,
                "min_colour_share": Graders.minColourShare,
                "pixel_art_colour_limit": Graders.pixelArtColourLimit,
            ],
            "images": images.map { ["candidate": $0.candidate, "file": $0.file, "pass": $0.pass, "scores": $0.scores] },
        ]
        let data = try JSONSerialization.data(withJSONObject: record, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: run.appendingPathComponent("regrade-avatar.json"))
        return images
    }

    // MARK: - insightLine: rewarm the one line the insight engine already chose

    /// One day as the insight engine sees it (`DailyInsightEngine.Input`).
    struct InsightCase: Decodable, Sendable {
        let id: String
        /// Which fixture user the day belongs to: `gain` (Alex) or `loss` (Sam).
        let user: String
        /// `lose`, `gain`, `maintain`, or `unknown` for a caller that does not know it;
        /// absent means the fixture user's own direction.
        let goalDirection: String?
        let caloriesEaten: Double
        let calorieTarget: Double
        let protein: Double
        let proteinTarget: Double
        let waterOz: Double
        let waterGoalOz: Double
        let steps: Int
        let stepGoal: Int
        let loggedAnythingToday: Bool
        let loggingStreakDays: Int
        let proteinHitStreakDays: Int
        let hydrationHitStreakDays: Int
        let workoutToday: Bool
        let hourOfDay: Int
        let daysAwayBeforeToday: Int
        /// The insight the engine must pick for this day (a dataset self-check).
        let insight: String
        /// The numbers of that insight's template, which the rewording must keep (a self-check).
        let keep: [Double]

        var reader: Graders.Reader { EvalFixtures.reader(user) }

        var input: DailyInsightEngine.Input {
            DailyInsightEngine.Input(
                caloriesEaten: caloriesEaten, calorieTarget: calorieTarget, protein: protein,
                proteinTarget: proteinTarget, waterOz: waterOz, waterGoalOz: waterGoalOz, steps: steps,
                stepGoal: stepGoal, loggedAnythingToday: loggedAnythingToday, loggingStreakDays: loggingStreakDays,
                proteinHitStreakDays: proteinHitStreakDays, hydrationHitStreakDays: hydrationHitStreakDays,
                workoutToday: workoutToday, hourOfDay: hourOfDay, daysAwayBeforeToday: daysAwayBeforeToday,
                goalDirection: EvalFixtures.direction(user, override: goalDirection))
        }

        /// The insight the card would show and the hint it would hand the phraser
        /// (`InsightCard.appear`: the template stands in for an empty hint).
        var chosen: (insight: DailyInsightEngine.Insight, hint: String)? {
            DailyInsightEngine.bestInsight(input).map { ($0, $0.factualHint.isEmpty ? $0.template : $0.factualHint) }
        }
    }

    func testInsightLine() async throws {
        try EvalEnv.requireLive()
        let cases = try EvalDataset.load("insight_line/v1.jsonl", as: InsightCase.self)
        try await EvalRunner.run(task: .insightLine, dataset: "insight_line/v1", cases: cases,
                                 caseID: { $0.id }) { item in
            await Self.insightAttempt(item)
        }
    }

    static func insightAttempt(_ item: InsightCase) async -> EvalOutcome {
        guard let chosen = item.chosen, chosen.insight.id == item.insight else {
            return EvalOutcome(ok: false, error: "dataset: engine picked \(item.chosen?.insight.id ?? "nothing"), case says \(item.insight)",
                               scores: [:], pass: false, output: "")
        }
        // nil covers a failed call and a reply the sanitiser rejected (a banned phrase, or
        // over 180 characters); the card then keeps the template, so both are "not used".
        let tap = await EvalRunner.recording {
            await InsightPhraser.rephrase(template: chosen.insight.template, factualHint: chosen.hint)
        }
        guard let line = tap.value ?? nil else {
            return .notUsed(raw: tap.raw, failure: tap.failure, discardedBy: "the sanitiser")
        }
        let graded = Graders.insightLine(template: chosen.insight.template, hint: chosen.hint, line: line,
                                         reader: item.reader)
        return EvalOutcome(ok: true, error: nil, scores: graded.scores, pass: graded.pass, output: line)
    }

    // MARK: - weeklyReflection: the weekly note, from day counts and the shape of the trend

    /// One week as the reflection sees it (`WeeklyReflection.Inputs`).
    struct WeeklyCase: Decodable, Sendable {
        let id: String
        let user: String
        /// `maintain` for the three cases that give a fixture user that goal; absent otherwise.
        let direction: String?
        let note: String
        let daysLogged: Int
        let ateEnoughDays: Int
        let proteinGoalDays: Int
        let waterGoalDays: Int
        let stepGoalDays: Int
        let workoutDays: Int
        /// `notEnoughData`, `steady`, `easingDown`, `droppingFast` or `climbing`.
        let trend: String
        /// Which opening the no-key template must choose for these counts (a dataset
        /// self-check): `consistency`, `fueled`, `protein`, `moved`, `checkedIn`, `freshPage`.
        let lead: String

        var reader: Graders.Reader { EvalFixtures.reader(user) }
        var counts: [Int] { [daysLogged, ateEnoughDays, proteinGoalDays, waterGoalDays, stepGoalDays, workoutDays] }

        var trendShape: WeeklyReflection.Inputs.TrendShape? {
            switch trend {
            case "notEnoughData": return .notEnoughData
            case "steady": return .steady
            case "easingDown": return .easingDown
            case "droppingFast": return .droppingFast
            case "climbing": return .climbing
            default: return nil
            }
        }

        var inputs: WeeklyReflection.Inputs? {
            guard let trendShape, let direction = EvalFixtures.direction(user, override: direction) else { return nil }
            return WeeklyReflection.Inputs(
                name: reader.name, direction: direction, note: note, daysLogged: daysLogged,
                ateEnoughDays: ateEnoughDays, proteinGoalDays: proteinGoalDays, waterGoalDays: waterGoalDays,
                stepGoalDays: stepGoalDays, workoutDays: workoutDays, trend: trendShape)
        }
    }

    func testWeeklyReflection() async throws {
        try EvalEnv.requireLive()
        let cases = try EvalDataset.load("weekly_reflection/v1.jsonl", as: WeeklyCase.self)
        try await EvalRunner.run(task: .weeklyReflection, dataset: "weekly_reflection/v1", cases: cases,
                                 caseID: { $0.id }) { item in
            await Self.weeklyAttempt(item)
        }
    }

    static func weeklyAttempt(_ item: WeeklyCase) async -> EvalOutcome {
        guard let inputs = item.inputs else {
            return EvalOutcome(ok: false, error: "dataset: \(item.id) does not map onto WeeklyReflection.Inputs",
                               scores: [:], pass: false, output: "")
        }
        // nil covers a failed call and a reply the sanitiser rejected (a banned phrase, a
        // digit, over 900 characters); `make` then shows the template.
        let tap = await EvalRunner.recording { await WeeklyReflection.written(inputs) }
        guard let note = tap.value ?? nil else {
            return .notUsed(raw: tap.raw, failure: tap.failure, discardedBy: "the sanitiser")
        }
        let graded = Graders.weeklyReflection(given: WeeklyReflection.userPrompt(inputs), counts: item.counts,
                                              name: inputs.name, text: note, reader: item.reader)
        return EvalOutcome(ok: true, error: nil, scores: graded.scores, pass: graded.pass, output: note)
    }

    // MARK: - onboardingNote: the closing note at the end of onboarding

    /// What the last onboarding screen hands the note (`OnboardingCoachMessage.Inputs`).
    struct OnboardingCase: Decodable, Sendable {
        let id: String
        let user: String
        /// Present (and empty) for the case of a person who gave no name.
        let name: String?
        /// A `GoalPace` raw value; the direction and the pace label come from it, as in onboarding.
        let pace: String
        /// An `ActivityLevel` raw value.
        let activity: String
        let note: String
        /// Phrases that name a goal other than the one the note is told.
        let mustNotSay: [String]

        var reader: Graders.Reader { EvalFixtures.reader(user, name: name) }

        var inputs: OnboardingCoachMessage.Inputs? {
            guard let pace = GoalPace(rawValue: pace), let activity = ActivityLevel(rawValue: activity) else { return nil }
            return OnboardingCoachMessage.Inputs(name: reader.name, direction: pace.direction, paceLabel: pace.label,
                                                 activityLabel: activity.label, note: note)
        }
    }

    func testOnboardingNote() async throws {
        try EvalEnv.requireLive()
        let cases = try EvalDataset.load("onboarding_note/v1.jsonl", as: OnboardingCase.self)
        try await EvalRunner.run(task: .onboardingNote, dataset: "onboarding_note/v1", cases: cases,
                                 caseID: { $0.id }) { item in
            await Self.onboardingAttempt(item)
        }
    }

    static func onboardingAttempt(_ item: OnboardingCase) async -> EvalOutcome {
        guard let inputs = item.inputs else {
            return EvalOutcome(ok: false, error: "dataset: \(item.id) does not map onto OnboardingCoachMessage.Inputs",
                               scores: [:], pass: false, output: "")
        }
        // nil covers a failed call and a reply the sanitiser rejected (a digit, or over
        // 700 characters); `make` then shows the template.
        let tap = await EvalRunner.recording { await OnboardingCoachMessage.written(inputs) }
        guard let note = tap.value ?? nil else {
            return .notUsed(raw: tap.raw, failure: tap.failure, discardedBy: "the sanitiser")
        }
        let graded = Graders.onboardingNote(given: OnboardingCoachMessage.userPrompt(inputs), name: inputs.name,
                                            mustNotSay: item.mustNotSay, text: note, reader: item.reader)
        return EvalOutcome(ok: true, error: nil, scores: graded.scores, pass: graded.pass, output: note)
    }

    // MARK: - memoryFold: older chat messages folded into the coach's notes and rolling summary

    /// One consolidation pass (`CoachMemoryService.consolidate`): the memory as it stands
    /// and the batch of messages leaving the window, with what the batch plants.
    struct MemoryCase: Decodable, Sendable {
        struct Message: Decodable, Sendable {
            /// `user` or `assistant`.
            let role: String
            let content: String
        }
        struct Retracted: Decodable, Sendable {
            let name: String
            let keywords: [String]
        }

        let id: String
        let user: String
        let currentNotes: String
        let currentSummary: String
        let messages: [Message]
        /// The durable facts the batch states: an allergy, an injury, a food preference, a schedule constraint.
        let facts: [Graders.PlantedFact]
        /// The fact the user states and later takes back (in two cases it is already in the notes).
        let retracted: Retracted
        /// Facts in `currentNotes` that the batch does not contradict.
        let existing: [Graders.PlantedFact]
        let smallTalk: [String]
        let mustNotStore: [String]

        var reader: Graders.Reader { EvalFixtures.reader(user) }

        /// The batch as the app snapshots it. The times are a fixed minute apart; nothing reads the clock.
        var snapshots: [CoachMemoryService.MessageSnapshot] {
            messages.enumerated().map { index, message in
                CoachMemoryService.MessageSnapshot(role: message.role, content: message.content,
                                                   createdAt: Date(timeIntervalSinceReferenceDate: Double(index) * 60))
            }
        }

        var expectation: Graders.MemoryExpectation {
            Graders.MemoryExpectation(currentNotes: currentNotes, currentSummary: currentSummary, facts: facts,
                                      retracted: retracted.keywords, existing: existing, smallTalk: smallTalk,
                                      mustNotStore: mustNotStore, reader: reader)
        }
    }

    func testMemoryFold() async throws {
        try EvalEnv.requireLive()
        let cases = try EvalDataset.load("memory_fold/v1.jsonl", as: MemoryCase.self)
        try await EvalRunner.run(task: .memoryFold, dataset: "memory_fold/v1", cases: cases,
                                 caseID: { $0.id }) { item in
            await Self.memoryAttempt(item)
        }
    }

    static func memoryAttempt(_ item: MemoryCase) async -> EvalOutcome {
        let tap = await EvalRunner.recording {
            await CoachMemoryService.consolidate(currentNotes: item.currentNotes, currentSummary: item.currentSummary,
                                                 olderMessages: item.snapshots, profileName: item.reader.name)
        }
        // nil with no reply is a failed call; nil with a reply is one `parse` could not read.
        // Either way the app leaves the memory as it was and the batch stays unfolded.
        guard let raw = tap.raw else {
            return EvalOutcome(ok: false, error: "the call failed" + (tap.failure.map { ": \($0)" } ?? ""),
                               scores: [:], pass: false, output: "")
        }
        let graded = Graders.memoryFold(raw: raw, expect: item.expectation)
        let stored = tap.value ?? nil
        return EvalOutcome(ok: stored != nil, error: stored == nil ? "the reply did not parse as {notes, summary}" : nil,
                           scores: graded.scores, pass: stored != nil && graded.pass,
                           output: String(raw.prefix(EvalRunner.outputLimit)))
    }

    // MARK: - progressSummary: the Progress tab recap, from the factual snapshot

    /// The facts `ProgressSummaryCard.buildSnapshot` puts into its snapshot. That builder is
    /// a private method of the view, so `snapshot` writes the same lines in the same words;
    /// a test holds every label here to the view's source.
    struct ProgressCase: Decodable, Sendable {
        let id: String
        let user: String
        /// `maintain` for the one case that gives a fixture user that goal; absent otherwise.
        let direction: String?
        // Weight: all absent when there are too few weigh-ins for a trend.
        let weightTrend: Double?
        let weeklyRate: Double?
        let goalWeight: Double?
        let stillToGo: Double?
        let projectedGoalDate: String?
        let weighIns: Int?
        // Nutrition: all absent when nothing was logged in the last seven days.
        let loggedDays: Int?
        let avgCalories: Int?
        let fuelTarget: Int?
        let proteinHitDays: Int?
        let proteinTarget: Int?
        // Activity
        let stepDays: Int?
        let avgSteps: Int?
        let stepGoal: Int?
        let workoutsThisWeek: Int?
        let streak: Int
        let bio: String?

        var reader: Graders.Reader { EvalFixtures.reader(user) }
        var goalDirection: GoalPace.Direction? { EvalFixtures.direction(user, override: direction) }

        static let noTrend = "Weight: not enough weigh-ins for a trend yet"
        static let noFood = "Nutrition: nothing logged in the last 7 days"

        var snapshot: String {
            let unit = UnitSystem.imperial.weightUnit
            func one(_ value: Double) -> String { String(format: "%.1f", value) }
            var lines: [String] = []
            if let weightTrend, let weeklyRate, let goalWeight, let weighIns, let goalDirection {
                lines.append("Weight trend: \(one(weightTrend)) \(unit)")
                lines.append("Weekly rate: \(one(weeklyRate)) \(unit)/wk (negative = losing)")
                lines.append("Goal weight: \(one(goalWeight)) \(unit) (goal direction: \(goalDirection))")
                if let stillToGo { lines.append("Still to go: \(one(stillToGo)) \(unit)") }
                if let projectedGoalDate { lines.append("Projected goal date: \(projectedGoalDate)") }
                lines.append("Total weigh-ins: \(weighIns)")
            } else {
                lines.append(Self.noTrend)
            }
            if let loggedDays, let avgCalories, let fuelTarget, let proteinHitDays, let proteinTarget {
                lines.append("Avg calories over \(loggedDays) logged day(s) this week: \(avgCalories) (fuel target \(fuelTarget))")
                lines.append("Protein goal reached on \(proteinHitDays) of \(loggedDays) logged day(s) (target \(proteinTarget)g)")
            } else {
                lines.append(Self.noFood)
            }
            if let stepDays, let avgSteps, let stepGoal {
                lines.append("Avg steps over \(stepDays) day(s): \(avgSteps) (goal \(stepGoal))")
            }
            if let workoutsThisWeek, workoutsThisWeek > 0 { lines.append("Workouts this week: \(workoutsThisWeek)") }
            lines.append("Current logging streak: \(streak) day(s)")
            if let bio, !bio.isEmpty { lines.append("About the user, from their own profile: \(bio)") }
            return lines.joined(separator: "\n")
        }
    }

    func testProgressSummary() async throws {
        try EvalEnv.requireLive()
        let cases = try EvalDataset.load("progress_summary/v1.jsonl", as: ProgressCase.self)
        try await EvalRunner.run(task: .progressSummary, dataset: "progress_summary/v1", cases: cases,
                                 caseID: { $0.id }) { item in
            await Self.progressAttempt(item)
        }
    }

    static func progressAttempt(_ item: ProgressCase) async -> EvalOutcome {
        let snapshot = item.snapshot
        let tap = await EvalRunner.recording { try await ProgressSummaryService.summary(snapshot: snapshot) }
        switch tap.result {
        case .failure(let error):
            // A reply the service could not decode, or a failed call: the card shows its error state.
            return .failed(error, output: tap.raw ?? "")
        case .success(let summary):
            let graded = Graders.progressSummary(snapshot: snapshot, summary: summary, reader: item.reader)
            return EvalOutcome(ok: true, error: nil, scores: graded.scores, pass: graded.pass,
                               output: ([summary.headline, summary.body] + summary.highlights.map { "- " + $0 })
                                   .joined(separator: "\n"))
        }
    }

    // MARK: - foodSuggestions: two or three picks for the current meal

    /// The engine's factual context (`FoodSuggestionEngine.Context`).
    struct FoodCase: Decodable, Sendable {
        struct TopFood: Decodable, Sendable {
            let name: String
            let count: Int
            let avgProteinG: Double
        }
        struct Place: Decodable, Sendable {
            let name: String
            let category: String?
        }

        let id: String
        let user: String
        /// `maintain` for the two cases that give a fixture user that goal; absent otherwise.
        let direction: String?
        let calorieTarget: Int
        let caloriesEaten: Int
        let proteinTarget: Int
        let proteinEaten: Int
        /// `breakfast`, `lunch`, `dinner` or `snack`.
        let mealSlot: String
        let topFoods: [TopFood]
        let underProteinTrend: Bool?
        let eatenToday: [String]
        let nearbyPlace: Place?
        /// The diet every logged food of the case keeps to, and foods outside it. The
        /// feature is not told a diet; these only feed the `avoided_foods_absent` score.
        let diet: String?
        let avoid: [String]?

        var reader: Graders.Reader { EvalFixtures.reader(user) }

        var context: FoodSuggestionEngine.Context? {
            guard let slot = FoodSuggestionEngine.MealSlot(rawValue: mealSlot),
                  let direction = FoodSuggestionEngine.Direction(rawValue: direction ?? (user == "gain" ? "gain" : "lose"))
            else { return nil }
            // "Remaining" is room to add, never negative, as `makeContext` computes it.
            return FoodSuggestionEngine.Context(
                name: reader.name, direction: direction,
                calorieTarget: calorieTarget, caloriesEaten: caloriesEaten,
                caloriesRemaining: max(0, calorieTarget - caloriesEaten),
                proteinTarget: proteinTarget, proteinEaten: proteinEaten,
                proteinRemaining: max(0, proteinTarget - proteinEaten),
                mealSlot: slot,
                topFoods: topFoods.map { .init(name: $0.name, count: $0.count, avgProteinG: $0.avgProteinG) },
                underProteinTrend: underProteinTrend, eatenToday: eatenToday,
                nearbyPlace: nearbyPlace.map { .init(name: $0.name, category: $0.category) })
        }

        var expectation: Graders.FoodExpectation {
            Graders.FoodExpectation(nearbyPlace: nearbyPlace?.name, topFoods: topFoods.map(\.name),
                                    eatenToday: eatenToday, avoid: avoid, reader: reader)
        }
    }

    func testFoodSuggestions() async throws {
        try EvalEnv.requireLive()
        let cases = try EvalDataset.load("food_suggestions/v1.jsonl", as: FoodCase.self)
        try await EvalRunner.run(task: .foodSuggestions, dataset: "food_suggestions/v1", cases: cases,
                                 caseID: { $0.id }) { item in
            await Self.foodAttempt(item)
        }
    }

    static func foodAttempt(_ item: FoodCase) async -> EvalOutcome {
        guard let context = item.context else {
            return EvalOutcome(ok: false, error: "dataset: \(item.id) does not map onto FoodSuggestionEngine.Context",
                               scores: [:], pass: false, output: "")
        }
        let tap = await EvalRunner.recording { try await FoodSuggestionService.suggestions(for: context) }
        switch tap.result {
        case .failure(let error):
            // A reply the service could not decode, or a failed call: the view shows its error state.
            return .failed(error, output: tap.raw ?? "")
        case .success(let suggestions):
            let rawCount = (EvalRunner.jsonObject(tap.raw)?["suggestions"] as? [Any])?.count
            let graded = Graders.foodSuggestions(suggestions, rawCount: rawCount, expect: item.expectation)
            let shown = suggestions.map { "[\($0.kind.rawValue)] \($0.emoji) \($0.title): \($0.detail)" }
            return EvalOutcome(ok: true, error: nil, scores: graded.scores, pass: graded.pass,
                               output: shown.joined(separator: "\n"))
        }
    }

    // MARK: - coachPrompts and checklistPlan: two structured features over the coach's data summary

    /// What both features are handed: a profile, its logs, its training sessions and the
    /// coach's notes. The two datasets hold the same sixteen situations.
    struct CoachDataCase: Decodable, Sendable {
        struct Session: Decodable, Sendable {
            /// Days before today (0 is today); a session has no date of its own in the dataset.
            let daysAgo: Int
            /// A `WorkoutKind` raw value.
            let kind: String
            /// `MuscleFocus` raw values (gym sessions only).
            let focuses: [String]
            let minutes: Int
            let notes: String
        }

        let id: String
        let user: String
        /// A `GoalPace` raw value for the cases that give a fixture user another goal; absent otherwise.
        let pace: String?
        /// Present (and empty) for the case of a person who gave no name.
        let name: String?
        /// The person's own about-me note (`UserProfile.onboardingNote`); may be empty.
        let bio: String
        /// The coach's durable notes (`CoachMemory.profileNotes`); may be empty.
        let memoryNotes: String
        let sessions: [Session]
        /// `fixture` for the fixture user's food, water and weigh-ins; `none` for nothing logged.
        let logging: String
        /// Words for the training the sessions, the bio and the notes describe.
        let routine: [String]

        var reader: Graders.Reader { EvalFixtures.reader(user, name: name) }

        struct Inputs {
            let profile: UserProfile
            let foods: [FoodEntry]
            let weights: [WeightEntry]
            let water: [WaterEntry]
            let sessions: [WorkoutSession]
            let memory: CoachMemory?
        }

        /// False when a raw value in the case is not one of the app's.
        var isWellFormed: Bool {
            ["fixture", "none"].contains(logging) && (pace.map { GoalPace(rawValue: $0) != nil } ?? true)
                && sessions.allSatisfy { WorkoutKind(rawValue: $0.kind) != nil
                    && $0.focuses.allSatisfy { MuscleFocus(rawValue: $0) != nil } }
        }

        @MainActor
        func inputs() -> Inputs {
            let fixture = EvalFixtures.user(user)
            let profile = fixture.profile
            if let name { profile.name = name }
            if let pace, let chosen = GoalPace(rawValue: pace) { profile.pace = chosen }
            profile.onboardingNote = bio
            let calendar = Calendar.current
            let noon = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: calendar.startOfDay(for: .now)) ?? .now
            let logged = logging == "fixture"
            return Inputs(
                profile: profile,
                foods: logged ? fixture.foods : [], weights: logged ? fixture.weights : [],
                water: logged ? fixture.water : [],
                sessions: sessions.map { session in
                    WorkoutSession(date: calendar.date(byAdding: .day, value: -session.daysAgo, to: noon) ?? noon,
                                   kind: WorkoutKind(rawValue: session.kind) ?? .other,
                                   focuses: session.focuses.compactMap(MuscleFocus.init(rawValue:)),
                                   durationMinutes: session.minutes, notes: session.notes)
                },
                memory: memoryNotes.isEmpty ? nil : CoachMemory(profileNotes: memoryNotes))
        }
    }

    /// The data summary both features build their user turn from, as each of them builds it.
    @MainActor
    static func coachDataSummary(_ inputs: CoachDataCase.Inputs) -> String {
        CoachContext.summary(profile: inputs.profile, foods: inputs.foods, weights: inputs.weights,
                             water: inputs.water, sessions: inputs.sessions)
    }

    func testCoachPrompts() async throws {
        try EvalEnv.requireLive()
        let cases = try EvalDataset.load("coach_prompts/v1.jsonl", as: CoachDataCase.self)
        try await EvalRunner.run(task: .coachPrompts, dataset: "coach_prompts/v1", cases: cases,
                                 caseID: { $0.id }) { item in
            await Self.coachPromptsAttempt(item)
        }
    }

    @MainActor
    static func coachPromptsAttempt(_ item: CoachDataCase) async -> EvalOutcome {
        let inputs = item.inputs()
        // The user turn `generate` sends, for the numbers a chip may state.
        let given = CoachPromptService.userPrompt(
            name: inputs.profile.name, direction: inputs.profile.pace.direction,
            dataSummary: coachDataSummary(inputs), bio: inputs.profile.onboardingNote,
            memoryNotes: inputs.memory?.profileNotes ?? "")
        let tap = await EvalRunner.recording {
            try await CoachPromptService.generate(profile: inputs.profile, foods: inputs.foods, weights: inputs.weights,
                                                  sessions: inputs.sessions, water: inputs.water, memory: inputs.memory)
        }
        switch tap.result {
        case .failure(let error):
            return .failed(error, output: tap.raw ?? "")
        case .success(let chips):
            // `prompts` shows the fixed list when cleaning leaves nothing.
            guard !chips.isEmpty else {
                return .notUsed(raw: tap.raw, failure: tap.failure, discardedBy: "the chip filter")
            }
            let raw = EvalRunner.jsonObject(tap.raw)?["prompts"] as? [String]
            let graded = Graders.coachPrompts(given: given, shown: chips, raw: raw, routine: item.routine,
                                              reader: item.reader)
            return EvalOutcome(ok: true, error: nil, scores: graded.scores, pass: graded.pass,
                               output: String((tap.raw ?? chips.joined(separator: "\n")).prefix(EvalRunner.outputLimit)))
        }
    }

    func testChecklistPlan() async throws {
        try EvalEnv.requireLive()
        let cases = try EvalDataset.load("checklist_plan/v1.jsonl", as: CoachDataCase.self)
        try await EvalRunner.run(task: .checklistPlan, dataset: "checklist_plan/v1", cases: cases,
                                 caseID: { $0.id }) { item in
            await Self.checklistAttempt(item)
        }
    }

    @MainActor
    static func checklistAttempt(_ item: CoachDataCase) async -> EvalOutcome {
        let inputs = item.inputs()
        // The user turn `make` sends, for the `no_number_outside_the_data` score.
        let given = ChecklistPlanService.userPrompt(
            name: inputs.profile.name, direction: inputs.profile.pace.direction,
            dataSummary: coachDataSummary(inputs), bio: inputs.profile.onboardingNote,
            memoryNotes: inputs.memory?.profileNotes ?? "")
        let tap = await EvalRunner.recording {
            try await ChecklistPlanService.make(profile: inputs.profile, foods: inputs.foods, weights: inputs.weights,
                                                sessions: inputs.sessions, water: inputs.water, memory: inputs.memory)
        }
        switch tap.result {
        case .failure(let error):
            // A reply the service could not decode, a plan the cleaning emptied, or a failed
            // call: the card keeps its preset chips.
            return .failed(error, output: tap.raw ?? "")
        case .success(let plan):
            let graded = Graders.checklistPlan(given: given, plan: plan, raw: EvalRunner.jsonObject(tap.raw),
                                               routine: item.routine, reader: item.reader)
            let shown = "tasks: " + plan.tasks.map(\.title).joined(separator: " | ")
                + "\nchips: " + plan.chips.map(\.title).joined(separator: " | ")
            return EvalOutcome(ok: true, error: nil, scores: graded.scores, pass: graded.pass,
                               output: String((tap.raw ?? shown).prefix(EvalRunner.outputLimit)))
        }
    }
}

/// `Evals/regrade-avatars.sh Evals/runs/<run>`: no model is called and nothing is spent, so a
/// grader that was wrong can be corrected against the very images it misjudged. Its own
/// class because it is not a live evaluation: `run.sh <Name>` runs `LiveEvals/test<Name>`.
final class AvatarRegrade: XCTestCase {
    func testAvatarRegrade() throws {
        guard let run = EvalEnv.regradeRun else {
            throw XCTSkip("no run to regrade (use Evals/regrade-avatars.sh)")
        }
        let images = try LiveEvals.regradeAvatars(in: run)
        XCTAssertFalse(images.isEmpty, "no saved characters under \(run.path)/avatars")
    }
}
