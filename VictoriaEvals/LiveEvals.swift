import Foundation
import XCTest
@testable import Victoria

/// Live evaluations: each runs the app's own code path for one task against every
/// configured candidate model. Skipped unless `Evals/run.sh` configured a run.
final class LiveEvals: XCTestCase {

    // MARK: - mealDescribe: typed meal → structured estimate, graded against USDA totals

    func testMealDescribe() async throws {
        try EvalEnv.requireLive()
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
            guard let reply = await DailyBriefService.rephrase(picked, name: item.name) else {
                return EvalOutcome(ok: false, error: "rephrase returned nil (call failed or guardrail rejected it)",
                                   scores: ["used": 0], pass: false, output: "")
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
}
