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
    /// and the Settings override that applies to it.
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
    /// (`docs/MODEL_CHOICES.md`); add a row only together with the EVAL_REPORT section
    /// that justifies it, and `AITaskModelTests` pins every resolved value.
    static let measuredDefaults: [AITask: [AIProvider: AITaskDefault]] = [:]

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
    /// Order: the user's Settings override for the task's tier (an explicit choice
    /// always wins) → the task's measured default → the tier default.
    static func model(for task: AITask, provider: AIProvider) -> String {
        if let override = modelOverride(for: provider, tier: task.tier) { return override }
        if let measured = measuredDefaults[task]?[provider] { return measured.model }
        // The OpenAI research pass needs a Responses model with the web_search tool,
        // which is a property of the call rather than of the price class.
        if task == .planResearch, provider == .openai { return OpenAIClient.researchModel }
        return model(for: provider, tier: task.tier)
    }

    /// The model a task runs on for the ACTIVE provider.
    static func model(for task: AITask) -> String { model(for: task, provider: provider) }
}
