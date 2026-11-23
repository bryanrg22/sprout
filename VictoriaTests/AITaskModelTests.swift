import XCTest
@testable import Victoria

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
        .dailyBrief:       ("claude-haiku-4-5-20251001", "gpt-4.1-mini"),
        .insightLine:      ("claude-haiku-4-5-20251001", "gpt-4.1-mini"),
        .weeklyReflection: ("claude-haiku-4-5-20251001", "gpt-4.1-mini"),
        .onboardingNote:   ("claude-haiku-4-5-20251001", "gpt-4.1-mini"),
        .memoryFold:       ("claude-haiku-4-5-20251001", "gpt-4.1-mini"),
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

    func testEveryMeasuredDefaultCitesItsEvalSection() {
        for (task, byProvider) in AIConfig.measuredDefaults {
            for (provider, choice) in byProvider {
                XCTAssertTrue(choice.evidence.hasPrefix("EVAL_REPORT "),
                              "\(task) on \(provider) must cite the section that measured it")
                XCTAssertFalse(choice.model.isEmpty)
            }
        }
    }

    func testSettingsOverrideForTheTierBeatsTheDefault() {
        AIConfig.setModelOverride("my-own-model", for: .openai, tier: .coach)
        XCTAssertEqual(AIConfig.model(for: .coachTurn, provider: .openai), "my-own-model")
        XCTAssertEqual(AIConfig.model(for: .mealPhoto, provider: .openai), "my-own-model")
        XCTAssertEqual(AIConfig.model(for: .dailyBrief, provider: .openai), "gpt-4.1-mini",
                       "an override of one tier leaves the others alone")
        XCTAssertEqual(AIConfig.model(for: .coachTurn, provider: .anthropic), "claude-sonnet-5",
                       "an override is per provider")
    }

    func testBlankOverrideFallsBackToTheDefault() {
        AIConfig.setModelOverride("   ", for: .anthropic, tier: .insight)
        XCTAssertEqual(AIConfig.model(for: .insightLine, provider: .anthropic), "claude-haiku-4-5-20251001")
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
