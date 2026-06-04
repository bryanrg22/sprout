import Foundation
import SwiftData

/// One checkable thing for a given day — a gentle "Today's checklist" task like a gym
/// session, a run, or a stretch. Deliberately about **movement / wellness / showing up**,
/// never about restricting food or hitting a weight. Each item belongs to a single day so
/// the dashboard card can show *today's* plan and start fresh tomorrow.
///
/// Every property has a default value so the model stays SwiftData-migration- and
/// CloudKit-ready (matching `BuddySnapshot`): older / partially-decoded rows simply read
/// as the sensible defaults below.
@Model
final class ChecklistItem {
    /// What she wants to do ("Gym", "Evening walk"). Free text — presets just prefill it.
    var title: String = ""

    /// SF Symbol shown in the row's tinted disc. Falls back to a neutral "checklist" glyph.
    var systemIcon: String = "checklist"

    /// The day this task belongs to. Always stored as `Calendar.startOfDay(for:)` so a
    /// same-day comparison is exact regardless of the time it was created.
    var day: Date = Date.now

    /// Whether she's checked it off.
    var done: Bool = false

    /// Manual ordering within a day (new items append after the current ones).
    var sortOrder: Int = 0

    init(title: String = "",
         systemIcon: String = "checklist",
         day: Date = .now,
         done: Bool = false,
         sortOrder: Int = 0) {
        self.title = title
        self.systemIcon = systemIcon
        // Normalize to the start of the day so "today" comparisons are always exact.
        self.day = Calendar.current.startOfDay(for: day)
        self.done = done
        self.sortOrder = sortOrder
    }
}

/// Quick-add presets for the checklist — warm, activity- and wellness-focused starters so
/// she can plan her day in a tap. **Intentionally only movement / rest / prep**, with
/// nothing about restricting food or chasing a number on the scale (keeps the anti-restriction
/// tone consistent with the rest of the app).
///
/// These are also the documented OFFLINE FALLBACK: when there's no API key (or any AI
/// failure), `ChecklistPlanService.fallback()` surfaces exactly this set as the quick-add
/// chips, so the card degrades gracefully to today's behavior.
struct ChecklistSuggestion: Identifiable, Hashable {
    let title: String
    let systemIcon: String

    var id: String { title }

    /// The starter set surfaced as tappable chips in the empty state and the "+ Add task" menu.
    static let all: [ChecklistSuggestion] = [
        ChecklistSuggestion(title: "Gym",        systemIcon: "dumbbell.fill"),
        ChecklistSuggestion(title: "Run",        systemIcon: "figure.run"),
        ChecklistSuggestion(title: "Walk",       systemIcon: "figure.walk"),
        ChecklistSuggestion(title: "Yoga",       systemIcon: "figure.yoga"),
        ChecklistSuggestion(title: "Stretch",    systemIcon: "figure.flexibility"),
        ChecklistSuggestion(title: "Meal prep",  systemIcon: "carrot.fill"),
        ChecklistSuggestion(title: "Sleep early", systemIcon: "bed.double.fill"),
    ]
}

// MARK: - ChecklistProposal bridging

/// Convenience bridges between the offline `ChecklistSuggestion` presets and the AI-facing
/// `ChecklistProposal` (defined in `ChecklistPlanService`), so the card can treat a static
/// preset and a Vita-proposed chip uniformly in its `ForEach`.
extension ChecklistProposal {
    /// Lift a static preset into a proposal (used for the fallback chip set).
    init(_ suggestion: ChecklistSuggestion) {
        self.init(title: suggestion.title, icon: suggestion.systemIcon)
    }
}

extension ChecklistSuggestion {
    /// The static presets expressed as proposals — the default chip row before (or without)
    /// a personalized plan.
    static var allProposals: [ChecklistProposal] { all.map { ChecklistProposal($0) } }
}
