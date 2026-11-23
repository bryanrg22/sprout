import Foundation
import UIKit
import XCTest
@testable import Victoria

/// Live evaluations: each runs the app's own code path for one task against every
/// configured candidate model. Skipped unless `Evals/run.sh` configured a run.
final class LiveEvals: XCTestCase {

    // MARK: - mealDescribe: typed meal → structured estimate, graded against USDA totals

    func testMealDescribe() async throws {
        try EvalEnv.requireLive()
        // v3 = v1's cases plus the label nutrients of the same USDA records; the pass rule is
        // still calories within 20%, and the four estimated nutrients are scored beside it.
        // v3 (the same cases with the label nutrients) is not built yet: the USDA fetch that
        // produces its truth was rate-limited, and nothing in it may come from memory. Until
        // `build_v3.py` has run on fetched data this stays on v1, which exists and is cited.
        let cases = try EvalDataset.load("meal_describe/v1.jsonl", as: Graders.MealTruth.self)
        try await EvalRunner.run(task: .mealDescribe, dataset: "meal_describe/v1", cases: cases,
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
}
