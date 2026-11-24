import SwiftData

/// The one list of persisted models. The app's container (`SproutApp`) and the tests'
/// in-memory container are both built from it, so a model registered here is in both and a
/// model missing here is in neither. `StoreVerificationTests` compares this list with the
/// `@Model` classes in the source tree and fails when the two differ.
enum AppSchema {
    static let models: [any PersistentModel.Type] = [
        UserProfile.self,
        WeightEntry.self,
        FoodEntry.self,
        WorkoutEntry.self,
        WaterEntry.self,
        ChatMessage.self,
        // Vita's long-term memory (durable notes + rolling conversation summary).
        CoachMemory.self,
        // The adaptive Plan — the AI-authored, evolving "understanding of you" (see docs/adaptive-plan.md).
        CoachPlan.self,
        StepsEntry.self,
        // Passive tracker data (Fitbit via the direct Google Health pipe, or
        // anything Apple Health carries): nightly sleep (+stages), auto-detected
        // workouts, daily recovery vitals. Never counts toward the streak.
        SleepEntry.self,
        DetectedWorkout.self,
        VitalsEntry.self,
        AchievementUnlock.self,
        InsightShown.self,
        // Buddy / accountability-buddy layer (data + sync foundation).
        BuddyLink.self,
        Nudge.self,
        BuddySnapshot.self,
        // Daily "Today's checklist" tasks (gym / run / etc).
        ChecklistItem.self,
        // The Workouts tab: a session + its per-machine exercise rows (flat sessionID link).
        WorkoutSession.self,
        ExerciseEntry.self,
    ]

    static var schema: Schema { Schema(models) }
}
