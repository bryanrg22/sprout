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
            StepsEntry.self,
            AchievementUnlock.self,
            InsightShown.self,
            // Buddy / accountability-buddy layer (data + sync foundation).
            BuddyLink.self,
            Nudge.self,
            BuddySnapshot.self,
            // Daily "Today's checklist" tasks (gym / run / etc).
            ChecklistItem.self,
        ])
        do {
            container = try ModelContainer(for: schema)
        } catch {
            // A fresh in-memory store is better than crashing on a migration hiccup.
            let fallback = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            container = try! ModelContainer(for: schema, configurations: fallback)
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .fontDesign(.rounded)
        }
        .modelContainer(container)
    }
}
