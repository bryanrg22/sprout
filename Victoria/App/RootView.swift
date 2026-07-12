import SwiftUI
import SwiftData

struct RootView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @Query private var profiles: [UserProfile]
    @Query(sort: \StepsEntry.date) private var stepEntries: [StepsEntry]
    // Passive tracker mirrors (Fitbit etc. via Apple Health) — refreshed the same way steps are.
    @Query(sort: \SleepEntry.date) private var sleepEntries: [SleepEntry]
    @Query(sort: \DetectedWorkout.date) private var detectedWorkouts: [DetectedWorkout]
    @Query(sort: \VitalsEntry.date) private var vitalsEntries: [VitalsEntry]

    private var profile: UserProfile? { profiles.first }

    /// DEBUG: `--demo-screen <workout|achievements>` deep-links straight to a
    /// quick-link screen (normally reached from the Dashboard) so it can be
    /// screenshotted in isolation. Never used in the normal flow.
    private var demoScreenArg: String? {
        guard let i = CommandLine.arguments.firstIndex(of: "--demo-screen"),
              i + 1 < CommandLine.arguments.count else { return nil }
        return CommandLine.arguments[i + 1]
    }

    @ViewBuilder
    private func demoScreen(_ name: String, profile: UserProfile) -> some View {
        switch name {
        case "workout":      WorkoutLogView()                                   // brings its own NavigationStack
        case "achievements": NavigationStack { AchievementsView(profile: profile) }
        case "buddy":        NavigationStack { BuddyHomeView() }
        default:             MainTabView(profile: profile)
        }
    }

    /// The active visual skin, from the profile — defaults to `.cute` for onboarding /
    /// first run (either look can be the first; Bryan switches to Cool in Settings).
    private var themeStyle: ThemeStyle { profile?.themeStyle ?? .cute }

    var body: some View {
        // Set the global skin BEFORE the subtree reads any Theme color; `.id` rebuilds
        // the subtree when the user flips themes so every token + the scheme re-resolve.
        Theme.current = themeStyle.skin
        return content
            .tint(Theme.brand)
            .preferredColorScheme(themeStyle.skin.colorScheme)
            .id(themeStyle)
    }

    private var content: some View {
        Group {
            if WidgetGalleryView.isRequested {
                WidgetGalleryView()                       // DEBUG: preview widgets for screenshots
            } else if let profile, profile.onboardingComplete, let screen = demoScreenArg {
                demoScreen(screen, profile: profile)      // DEBUG: deep-link to a quick-link screen
                    .transition(.opacity)
            } else if let profile, profile.onboardingComplete {
                MainTabView(profile: profile)
                    .transition(.opacity)
            } else {
                OnboardingView(existing: profile)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut, value: profile?.onboardingComplete)
        .task {
            DemoSeed.seedIfNeeded(context, hasProfile: profile != nil)
            Diagnostics.shared.log("app launched (onboarded=\(profile?.onboardingComplete == true))", .app)
            // Backfill the last 30 days of REAL per-day step totals from Apple Health on launch,
            // so the Progress average reflects full days — not the partial/missing history that
            // `importTodaySteps` alone left behind (it only ever captured "today so far").
            if HealthKitService.isAvailable {
                await HealthKitService.shared.importRecentSteps(days: 30, into: context, existing: stepEntries)
                // Tracker data (Fitbit etc. bridged into Apple Health): last 2 weeks of
                // sleep (+stages), auto-detected workouts, and daily recovery vitals.
                await HealthKitService.shared.importRecentSleep(days: 14, into: context, existing: sleepEntries)
                await HealthKitService.shared.importRecentDetectedWorkouts(days: 14, into: context, existing: detectedWorkouts)
                await HealthKitService.shared.importRecentVitals(days: 14, into: context, existing: vitalsEntries)
            }
            // Direct Fitbit pipe (Google Health API) — runs AFTER HealthKit so its richer
            // stage/vitals numbers win the per-day upsert on any overlapping day.
            // (refresh() re-reads existing rows itself — the imports above may have
            // just inserted rows that our captured @Query arrays don't include.)
            if GoogleHealthSync.isConnected {
                await GoogleHealthSync.refresh(days: 14, into: context)
            }
            WidgetDataWriter.refresh(context: context, profile: profile)
            // Ask for notification permission + (re)build gentle reminders once on launch.
            if let profile, profile.onboardingComplete {
                await NotificationService.refreshOnLaunch(for: profile)
            }
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                Diagnostics.shared.log("app active", .app)
                // Re-pull steps on every foreground, then refresh the widget with fresh data.
                Task {
                    if HealthKitService.isAvailable {
                        // Re-pull the last 7 days (not just today) so yesterday gets finalized to
                        // its FULL total when she reopens the app the next day — the exact case
                        // where a day was frozen at a partial count.
                        await HealthKitService.shared.importRecentSteps(days: 7, into: context, existing: stepEntries)
                        // Tracker sleep/workouts/vitals land in Health whenever the bridge runs —
                        // re-pull a week on every foreground so last night shows up by morning.
                        await HealthKitService.shared.importRecentSleep(days: 7, into: context, existing: sleepEntries)
                        await HealthKitService.shared.importRecentDetectedWorkouts(days: 7, into: context, existing: detectedWorkouts)
                        await HealthKitService.shared.importRecentVitals(days: 7, into: context, existing: vitalsEntries)
                    }
                    if GoogleHealthSync.isConnected {
                        await GoogleHealthSync.refresh(days: 7, into: context)
                    }
                    WidgetDataWriter.refresh(context: context, profile: profile)
                }
            case .background:
                Diagnostics.shared.log("app background", .app)
                // Refresh on leave too, so the widget reflects what she just logged.
                WidgetDataWriter.refresh(context: context, profile: profile)
            default:
                break
            }
        }
    }
}

struct MainTabView: View {
    @Bindable var profile: UserProfile
    @State private var selection = DemoSeed.initialTab
    /// Shared "Ask Vita about this" bus: a long-press on any card sets a topic here, which
    /// flips us to the Vita tab so the coach can explain that component.
    @State private var askVita = AskVitaCenter()
    /// "What's New" sheet — shown once per marketing version (see `WhatsNew`).
    @State private var showWhatsNew = false
    // Sorted newest-first so `coachPlans.first` is the CURRENT plan (matches CoachPlan.current /
    // PlanCard) — `syncPlanTargets` mirrors that plan's targets, so an unsorted `.first` could
    // mirror a stale plan if CloudKit ever transiently has two rows.
    @Query(sort: \CoachPlan.updatedAt, order: .reverse) private var coachPlans: [CoachPlan]

    var body: some View {
        TabView(selection: $selection) {
            DashboardView(profile: profile)
                .tabItem { Label("Today", systemImage: "house.fill") }.tag(0)

            FoodLogView(profile: profile)
                .tabItem { Label("Nutrients", systemImage: "fork.knife") }.tag(1)

            WeightView(profile: profile)
                .tabItem { Label("Progress", systemImage: "chart.line.uptrend.xyaxis") }.tag(2)

            WorkoutsView()
                .tabItem { Label("Workouts", systemImage: "dumbbell.fill") }.tag(3)

            CoachView(profile: profile)
                .tabItem { Label(profile.coachName, systemImage: "sparkles") }.tag(4)
        }
        .environment(askVita)
        // Keep my buddy snapshot fresh app-wide — publish the moment I log on ANY tab (debounced) and
        // when the app backgrounds, not only while the Buddy page is open. (See `BuddyAutoPublisher`.)
        .background(BuddyAutoPublisher())
        // Five tabs is iOS's max before it collapses the rest into a "More" list — which would bury
        // Vita (the flagship coach). So the bar is Today · Nutrients · Progress · Workouts · Vita,
        // and Buddy lives as a Dashboard quick-link (it was one before, and stays one tap away).
        // When a long-press asks Vita about something, jump to her tab so she can answer (tag 4).
        .onChange(of: askVita.pendingTopic) { _, topic in
            if topic != nil { selection = 4 }
        }
        // "What's New" once per update — a celebratory rundown of the release. The adaptive-plan
        // invite is intentionally NOT chained here: building a plan is something the user opts into
        // from the "Build my plan" card on Progress, never an auto-popping dialog the instant they
        // land on Today (it read as intrusive + ugly stacked right on top of the home screen).
        .sheet(isPresented: $showWhatsNew, onDismiss: { WhatsNew.markSeen() }) {
            WhatsNewView(release: WhatsNew.current)
        }
        .task {
            if WhatsNew.shouldShow() { showWhatsNew = true }
            syncPlanTargets()
        }
        // Keep the app's targets mirroring the plan whenever it's built / reviewed / edited (any of
        // those bumps updatedAt), so a change Vita makes to the plan reflects everywhere instantly.
        .onChange(of: coachPlans.first?.updatedAt) { _, _ in syncPlanTargets() }
        // Settings now lives behind the pixel-avatar button in the Dashboard header.
    }

    /// Mirror the active plan's targets into the profile overrides — the single source of truth the
    /// rings / achievements / Vita context all read through `dailyCalorieTarget` / `macroTargets`.
    /// No plan (or no targets set) → 0, which falls back to the computed defaults.
    private func syncPlanTargets() {
        let plan = coachPlans.first
        let newCalorie = (plan?.hasRange == true) ? (plan?.calorieMin ?? 0) : 0
        let newCalorieMax = (plan?.hasRange == true) ? (plan?.calorieMax ?? 0) : 0
        let newProtein = max(0, plan?.proteinTarget ?? 0)
        if profile.calorieTargetOverride != newCalorie { profile.calorieTargetOverride = newCalorie }
        if profile.calorieMaxOverride != newCalorieMax { profile.calorieMaxOverride = newCalorieMax }
        if profile.proteinTargetOverride != newProtein { profile.proteinTargetOverride = newProtein }
    }
}
