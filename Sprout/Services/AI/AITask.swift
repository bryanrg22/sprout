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
        // Vita's chat turn: over 30 multi-turn conversations run through CoachTurnEngine a blind
        // judge preferred claude-haiku-5-5 to claude-sonnet-5, 50 to 15 (net +0.39, +0.20 to
        // +0.58), with every reply usable and the right tool as often or more; on the first
        // turn alone it chose the right tool 102/102 twice and 101/102 (EVAL_REPORT 10). About
        // an eighteenth of the cost and twice as fast (EVAL_REPORT 37). Switched by the
        // owner's decision before the judge was checked against the owner's labels (EVAL_REPORT 38).
        .coachTurn: [.anthropic: AITaskDefault(model: "claude-haiku-5-5", evidence: "EVAL_REPORT 37")],
        // The chat chips: both 100% on the rules, and the judge leaned to claude-haiku-5-5 (25 to
        // 13, +0.25, -0.04 to +0.54), an interval that does not favour the shipped model, at a
        // twenty-first of the cost (EVAL_REPORT 36, decided in 38).
        .coachPrompts: [.anthropic: AITaskDefault(model: "claude-haiku-5-5", evidence: "EVAL_REPORT 36")],
        // The daily brief: claude-haiku-5-5 and claude-sonnet-5 both keep the numbers (rules 97%
        // and 100%), but a blind judge preferred claude-sonnet-5 20 to 2 (+0.24 to +0.70): the
        // cheaper model broke the brief's own format and once dropped a number (EVAL_REPORT 39).
        // About $1.40 per 1,000 briefs, one a day. OpenAI: EVAL_REPORT 10.
        .dailyBrief: [
            .anthropic: AITaskDefault(model: "claude-sonnet-5", evidence: "EVAL_REPORT 39"),
            .openai: AITaskDefault(model: "gpt-6-luna", evidence: "EVAL_REPORT 10"),
        ],
        // Short-writing tasks. Anthropic: claude-haiku-5-5 (thinking off, EVAL_REPORT 25)
        // passed as often as claude-haiku-4-5 or more, 5 repeats on the current prompts, at a
        // seventh of the cost and faster (EVAL_REPORT 35). OpenAI: each replaced the deprecated
        // gpt-4.1-mini with the cheapest candidate within noise of the best (EVAL_REPORT 22).
        // The insight line moved up again: against claude-sonnet-5 the judge preferred it 21 to 6
        // (+0.05 to +0.47) with the rules equal (EVAL_REPORT 39); one line a day.
        .insightLine: [
            .anthropic: AITaskDefault(model: "claude-sonnet-5", evidence: "EVAL_REPORT 39"),
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
        // The memory fold: claude-sonnet-5. Against claude-haiku-5-5 the rules are equal (every
        // fact kept, no app-owned figure stored, now removed in code, EVAL_REPORT 36) and a blind
        // judge preferred its notes 23 to 8 (+0.06 to +0.75): tighter catch-ups, cleaner
        // retractions. It guessed a gender in 2 of 36 folds (EVAL_REPORT 39). OpenAI: gpt-6-luna
        // kept every planted fact in only 78% of runs (EVAL_REPORT 22).
        .memoryFold: [
            .anthropic: AITaskDefault(model: "claude-sonnet-5", evidence: "EVAL_REPORT 39"),
            .openai: AITaskDefault(model: "gpt-5.6-luna", evidence: "EVAL_REPORT 22"),
        ],
        // The checklist: claude-sonnet-5-5 against claude-sonnet-5, rules equal (100%), a blind
        // judge preferred it 23 to 9 (+0.29, 0.00 to +0.56), and it is a little cheaper and
        // faster (EVAL_REPORT 39). claude-haiku-5-5 lost to claude-sonnet-5 (EVAL_REPORT 36).
        .checklistPlan: [.anthropic: AITaskDefault(model: "claude-sonnet-5-5", evidence: "EVAL_REPORT 39")],
        // A typed meal: on household measures (meal_describe/v4) claude-sonnet-5-5 is within 20%
        // as often as claude-sonnet-5 (94% each) at about 30% less, and faster (EVAL_REPORT 39);
        // claude-haiku-5-5 was worse (EVAL_REPORT 37).
        .mealDescribe: [.anthropic: AITaskDefault(model: "claude-sonnet-5-5", evidence: "EVAL_REPORT 39")],
        // The plan's web research: a blind judge preferred claude-opus-5-5's brief to
        // claude-opus-4-8's 6 to 0 (+0.75, +0.38 to +1.00) on 8 cases, every brief searched,
        // at about 15% less (EVAL_REPORT 39).
        .planResearch: [.anthropic: AITaskDefault(model: "claude-opus-5-5", evidence: "EVAL_REPORT 39")],
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
