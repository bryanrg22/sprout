import SwiftUI
import SwiftData

@main
struct VictoriaApp: App {
    /// Bridges UIKit for remote-notification registration (CloudKit push of buddy nudges).
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    let container: ModelContainer

    init() {
        let schema = Schema([
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
            // Passive tracker data mirrored from Apple Health (Fitbit etc. via a bridge):
            // nightly sleep (+stages), auto-detected workouts, daily recovery vitals.
            // Never counts toward the streak.
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
        ])
        do {
            container = try ModelContainer(for: schema)
        } catch {
            // A fresh in-memory store is better than crashing on a migration hiccup — but it
            // ALSO means the user silently re-onboards and everything they enter evaporates on
            // relaunch. Leave a loud trace so a field report ("it made me start over") is
            // diagnosable instead of a mystery.
            Diagnostics.shared.log("CRITICAL: SwiftData store failed to open — running IN-MEMORY (data will not persist): \(error.localizedDescription)", .error)
            let fallback = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            container = try! ModelContainer(for: schema, configurations: fallback)
        }

        #if DEBUG
        // DEBUG-ONLY: let an automated / simulator run inject a Claude key via the
        // `SPROUT_ANTHROPIC_KEY` env var (passed as `SIMCTL_CHILD_SPROUT_ANTHROPIC_KEY`) so the
        // live AI can be tested end-to-end. This whole block is compiled OUT of Release /
        // Archive builds (`#if DEBUG`), so it can NEVER reach TestFlight or the App Store.
        if let raw = ProcessInfo.processInfo.environment["SPROUT_ANTHROPIC_KEY"] {
            let testKey = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if !testKey.isEmpty { KeychainStore.setAPIKey(testKey, for: .anthropic) }
        }
        #endif
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .fontDesign(.rounded)
        }
        .modelContainer(container)
    }
}
