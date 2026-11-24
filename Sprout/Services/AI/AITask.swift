import Foundation

/// Every model-backed task in the app, one case per distinct prompt + output contract.
///
/// A task is the unit a model is chosen for and the unit an evaluation measures
/// (`Evals/`, results in `docs/EVAL_REPORT.md`). A call site names its task and asks
/// `AIConfig.model(for:)` for the model; it never names a model or a tier itself.
enum AITask: String, CaseIterable, Sendable {
    /// Vita's chat turn: prose, or one tool call from `CoachTools.schemas`.
    case coachTurn
    /// Meal photo(s) → structured nutrition estimate.
    case mealPhoto
    /// Typed or spoken meal description → the same structured estimate.
    case mealDescribe
    /// 2–3 additive food suggestions from today's gaps.
    case foodSuggestions
    /// The Progress tab recap (headline, body, highlights).
    case progressSummary
    /// Today's personalized checklist tasks and quick-add chips.
    case checklistPlan
    /// The quick-prompt chips above the chat field.
    case coachPrompts
    /// Authoring the adaptive plan.
    case planBuild
    /// Re-emitting the plan against newer data.
    case planReview
    /// The web-search research pass that grounds a plan build.
    case planResearch
    /// Rewarming the once-a-day brief the template engine already chose.
    case dailyBrief
    /// Rephrasing the single insight line.
    case insightLine
    /// The weekly reflection note.
    case weeklyReflection
    /// The closing note at the end of onboarding.
    case onboardingNote
    /// Folding older chat messages into long-term memory.
    case memoryFold

    /// The price class a task falls back to when it has no measured default of its own,
    /// which is also its tier in `AIConfig.model(for:tier:)`.
    var tier: AIConfig.ModelTier {
        switch self {
        case .coachTurn, .mealPhoto, .mealDescribe, .foodSuggestions, .progressSummary,
             .checklistPlan, .coachPrompts:
            return .coach
        case .planBuild, .planReview, .planResearch:
            return .plan
        case .dailyBrief, .insightLine, .weeklyReflection, .onboardingNote, .memoryFold:
            return .insight
        }
    }
}

/// A task's default model on one provider, with the measurement that chose it.
struct AITaskDefault: Sendable, Equatable {
    let model: String
    /// The `docs/EVAL_REPORT.md` section that measured this choice, e.g. "EVAL_REPORT 4".
    let evidence: String
}

extension AIConfig {
    /// Per-task defaults chosen by measurement. A task absent from this table uses its
    /// tier's default, which was chosen by price and release notes rather than measured
    /// (not measured); add a row only together with the EVAL_REPORT section
    /// that justifies it, and `AITaskModelTests` pins every resolved value.
    static let measuredDefaults: [AITask: [AIProvider: AITaskDefault]] = [
        // 13 cases x 3 repeats, three runs: both pass every case at a fraction of the price of
        // the tier default (gpt-4.1-mini passed 77-92% and is deprecated; haiku-4-5 costs 7x).
        .dailyBrief: [
            .anthropic: AITaskDefault(model: "claude-haiku-5-5", evidence: "EVAL_REPORT 10"),
            .openai: AITaskDefault(model: "gpt-6-luna", evidence: "EVAL_REPORT 10"),
        ],
        // Three short-writing tasks. Anthropic: claude-haiku-5-5 (thinking off, EVAL_REPORT 25)
        // passed as often as claude-haiku-4-5 or more, 5 repeats on the current prompts, at a
        // seventh of the cost and faster (EVAL_REPORT 35). OpenAI: each replaced the deprecated
        // gpt-4.1-mini with the cheapest candidate within noise of the best (EVAL_REPORT 22).
        .insightLine: [
            .anthropic: AITaskDefault(model: "claude-haiku-5-5", evidence: "EVAL_REPORT 35"),
            .openai: AITaskDefault(model: "gpt-6-luna", evidence: "EVAL_REPORT 22"),
        ],
        .weeklyReflection: [
            .anthropic: AITaskDefault(model: "claude-haiku-5-5", evidence: "EVAL_REPORT 35"),
            .openai: AITaskDefault(model: "gpt-6-luna", evidence: "EVAL_REPORT 22"),
        ],
        .onboardingNote: [
            .anthropic: AITaskDefault(model: "claude-haiku-5-5", evidence: "EVAL_REPORT 35"),
            .openai: AITaskDefault(model: "gpt-6-luna", evidence: "EVAL_REPORT 22"),
        ],
        // The memory fold stays on the Anthropic tier default: claude-haiku-5-5 passes as often
        // but stores a number the app owns in 20% of folds, against a gendered pronoun in 28%
        // for claude-haiku-4-5; which defect is worse is the owner's call (EVAL_REPORT 35).
        // OpenAI: gpt-6-luna kept every planted fact in only 78% of runs (EVAL_REPORT 22).
        .memoryFold: [.openai: AITaskDefault(model: "gpt-5.6-luna", evidence: "EVAL_REPORT 22")],
        // The recap: claude-sonnet-5 passed 88% against 80% for claude-haiku-5-5, whose failures
        // were mostly its own arithmetic on the person's figures (EVAL_REPORT 35). Kept, now
        // by measurement; accuracy of the numbers is the point of this card.
        .progressSummary: [.anthropic: AITaskDefault(model: "claude-sonnet-5", evidence: "EVAL_REPORT 35")],
    ]

    /// Rows of a defaults table that do not say which EVAL_REPORT section measured them.
    /// The rule is a function of the table so it can be tested on a table that breaks it.
    static func uncitedDefaults(in table: [AITask: [AIProvider: AITaskDefault]]) -> [String] {
        table.flatMap { task, byProvider in
            byProvider.compactMap { provider, choice in
                let cited = choice.evidence.hasPrefix("EVAL_REPORT ")
                    && Int(choice.evidence.dropFirst("EVAL_REPORT ".count)) != nil
                return (cited && !choice.model.isEmpty) ? nil : "\(task.rawValue)/\(provider.rawValue)"
            }
        }.sorted()
    }

    /// The model a task runs on for a provider.
    ///
    /// Order: the task's measured default → the tier default. (A scoped `AIRuntime.model`,
    /// used by evaluations, replaces it inside the clients.)
    static func model(for task: AITask, provider: AIProvider) -> String {
        if let measured = measuredDefaults[task]?[provider] { return measured.model }
        // The OpenAI research pass needs a Responses model with the web_search tool,
        // which is a property of the call rather than of the price class.
        if task == .planResearch, provider == .openai { return OpenAIClient.researchModel }
        return model(for: provider, tier: task.tier)
    }

    /// The model a task runs on for the ACTIVE provider.
    static func model(for task: AITask) -> String { model(for: task, provider: provider) }
}
