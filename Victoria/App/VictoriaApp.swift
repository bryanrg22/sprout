import SwiftUI
import SwiftData

@main
struct VictoriaApp: App {
    /// Bridges UIKit for remote-notification registration (CloudKit push of buddy nudges).
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    let container: ModelContainer

    init() {
        // The model list lives in `AppSchema` (one source of truth, shared with the tests).
        let schema = AppSchema.schema
        #if DEBUG
        // UI smoke flows (`--ui-testing`): an in-memory store with CloudKit off, and a
        // scripted (or keyless) AI runtime. Returns before anything below can open the
        // real store or read a key; a failure here stops the launch rather than falling
        // through to the real store. See `UITestHooks`.
        if UITestHooks.isActive {
            // Before anything reads a default (the views' stored settings, the day caches).
            UITestHooks.resetDefaultsIfAsked()
            do {
                container = try UITestHooks.makeContainer()
            } catch {
                fatalError("--ui-testing: the in-memory store failed to open: \(error)")
            }
            UITestHooks.installAIRuntime()
            if UITestHooks.current.simulateStoreFailure {
                StoreStatus.recordOpenFailure(UITestHooks.SimulatedStoreFailure())
            }
            return
        }
        #endif
        do {
            container = try ModelContainer(for: schema)
        } catch {
            // A fresh in-memory store is better than crashing on a migration hiccup — but it
            // ALSO means the user silently re-onboards and everything they enter evaporates on
            // relaunch. Leave a loud trace so a field report ("it made me start over") is
            // diagnosable instead of a mystery.
            Diagnostics.shared.log("CRITICAL: SwiftData store failed to open — running IN-MEMORY (data will not persist): \(error.localizedDescription)", .error)
            // The launch shows `StoreUnavailableView`, never onboarding: the person's data is
            // still in the file, and onboarding on an empty stand-in would start them over.
            StoreStatus.recordOpenFailure(error)
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
