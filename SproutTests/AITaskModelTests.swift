import XCTest
@testable import Sprout

/// Which model every task runs on. The table below is the shipped behaviour; a
/// default changes only together with the EVAL_REPORT section that measured it, and
/// this test is edited in the same change.
final class AITaskModelTests: XCTestCase {

    private let overrideKeys = [
        "ai_model_anthropic_coach", "ai_model_anthropic_insight", "ai_model_anthropic_plan",
        "ai_model_openai_coach", "ai_model_openai_insight", "ai_model_openai_plan",
    ]
    private var saved: [String: String] = [:]

    override func setUp() {
        super.setUp()
        // The hosted test app shares the real defaults domain: park any override a
        // developer typed into Settings so the pinned defaults are what is measured.
        for key in overrideKeys {
            if let value = UserDefaults.standard.string(forKey: key) { saved[key] = value }
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    override func tearDown() {
        for key in overrideKeys {
            if let value = saved[key] { UserDefaults.standard.set(value, forKey: key) }
            else { UserDefaults.standard.removeObject(forKey: key) }
        }
        saved = [:]
        super.tearDown()
    }

    private let expected: [AITask: (anthropic: String, openai: String)] = [
        .coachTurn:        ("claude-sonnet-5", "gpt-5.6-terra"),
        .mealPhoto:        ("claude-sonnet-5", "gpt-5.6-terra"),
        .mealDescribe:     ("claude-sonnet-5", "gpt-5.6-terra"),
        .foodSuggestions:  ("claude-sonnet-5", "gpt-5.6-terra"),
        .progressSummary:  ("claude-sonnet-5", "gpt-5.6-terra"),
        .checklistPlan:    ("claude-sonnet-5", "gpt-5.6-terra"),
        .coachPrompts:     ("claude-sonnet-5", "gpt-5.6-terra"),
        .planBuild:        ("claude-opus-4-8", "gpt-5.6-sol"),
        .planReview:       ("claude-opus-4-8", "gpt-5.6-sol"),
        .planResearch:     ("claude-opus-4-8", "gpt-5.6-sol"),
        .dailyBrief:       ("claude-haiku-5-5", "gpt-6-luna"),            // EVAL_REPORT 10
        .insightLine:      ("claude-haiku-4-5-20251001", "gpt-6-luna"),    // EVAL_REPORT 22
        .weeklyReflection: ("claude-haiku-4-5-20251001", "gpt-6-luna"),    // EVAL_REPORT 22
        .onboardingNote:   ("claude-haiku-4-5-20251001", "gpt-6-luna"),    // EVAL_REPORT 22
        .memoryFold:       ("claude-haiku-4-5-20251001", "gpt-5.6-luna"),  // EVAL_REPORT 22
    ]

    func testEveryTaskHasAPinnedDefault() {
        XCTAssertEqual(Set(expected.keys), Set(AITask.allCases),
                       "a new task needs a row here and in docs/EVAL_REPORT.md")
    }

    func testResolvedDefaultsMatchTheTable() {
        for task in AITask.allCases {
            guard let want = expected[task] else { continue }
            XCTAssertEqual(AIConfig.model(for: task, provider: .anthropic), want.anthropic, "\(task) on Anthropic")
            XCTAssertEqual(AIConfig.model(for: task, provider: .openai), want.openai, "\(task) on OpenAI")
        }
    }

    /// gpt-4.1-mini is deprecated and stops answering on 2027-01-14 (EVAL_REPORT 6).
    func testNoTaskDefaultsToTheDeprecatedMini() {
        for task in AITask.allCases {
            XCTAssertNotEqual(AIConfig.model(for: task, provider: .openai), "gpt-4.1-mini", "\(task)")
        }
    }

    func testEveryMeasuredDefaultCitesItsEvalSection() {
        XCTAssertEqual(AIConfig.uncitedDefaults(in: AIConfig.measuredDefaults), [])
    }

    func testTheCitationRuleRejectsRowsWithoutASection() {
        // The shipped table may be empty, so the rule is exercised on a table that breaks it.
        let table: [AITask: [AIProvider: AITaskDefault]] = [
            .dailyBrief: [.openai: AITaskDefault(model: "gpt-6-luna", evidence: "EVAL_REPORT 9"),
                          .anthropic: AITaskDefault(model: "claude-haiku-5-5", evidence: "seemed fine")],
            .mealPhoto: [.openai: AITaskDefault(model: "", evidence: "EVAL_REPORT 10")],
            .coachTurn: [.anthropic: AITaskDefault(model: "claude-sonnet-5-5", evidence: "EVAL_REPORT ")],
        ]
        XCTAssertEqual(AIConfig.uncitedDefaults(in: table),
                       ["coachTurn/anthropic", "dailyBrief/anthropic", "mealPhoto/openai"])
    }

    func testTheAppHasNoModelSettingOnlyAScopedRuntimeChangesTheModel() {
        // The measured default stands; only an evaluation's scoped model replaces it, and
        // only inside the clients (`AIRuntime.resolve`).
        XCTAssertEqual(AIConfig.model(for: .dailyBrief, provider: .anthropic), "claude-haiku-5-5")
        XCTAssertEqual(AIRuntime.resolve(model: "claude-haiku-5-5"), "claude-haiku-5-5")
        AIRuntime.$current.withValue(AIRuntime(model: "claude-sonnet-5")) {
            XCTAssertEqual(AIRuntime.resolve(model: "claude-haiku-5-5"), "claude-sonnet-5")
        }
    }

    func testActiveProviderResolutionFollowsTheScopedProvider() {
        AIRuntime.$current.withValue(AIRuntime(provider: .openai)) {
            XCTAssertEqual(AIConfig.model(for: .planBuild), "gpt-5.6-sol")
            XCTAssertEqual(AIConfig.planModel, "gpt-5.6-sol")
            XCTAssertEqual(AIConfig.coachModel, "gpt-5.6-terra")
        }
        AIRuntime.$current.withValue(AIRuntime(provider: .anthropic)) {
            XCTAssertEqual(AIConfig.model(for: .planBuild), "claude-opus-4-8")
            XCTAssertEqual(AIConfig.insightModel, "claude-haiku-4-5-20251001")
        }
    }
}
