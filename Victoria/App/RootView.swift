import SwiftUI
import SwiftData

struct RootView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @Query private var profiles: [UserProfile]
    @Query(sort: \StepsEntry.date) private var stepEntries: [StepsEntry]
    // Passive tracker mirrors (direct Google Health pipe and/or Apple Health) —
    // refreshed the same way steps are.
    @Query(sort: \SleepEntry.date) private var sleepEntries: [SleepEntry]
    @Query(sort: \DetectedWorkout.date) private var detectedWorkouts: [DetectedWorkout]
    @Query(sort: \VitalsEntry.date) private var vitalsEntries: [VitalsEntry]

    /// Single-flight guard for the tracker-data refresh. At cold launch BOTH `.task`
    /// and the scenePhase `.active` handler fire; two concurrent passes would each
    /// snapshot `existing` rows before the other's inserts land — the classic
    /// duplicate-row race — and could interleave the HealthKit and Google merges out
    /// of order (Google must run AFTER HealthKit so its richer data wins the upsert).
    /// The second caller just skips; the next foreground catches anything missed.
    @State private var trackerRefreshInFlight = false

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
    /// first run (Victoria is the primary user; Bryan switches to Cool in Settings).
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
            // Travel awareness: one timezone comparison — powers the jet-lag framing in
            // Vita's context and the daily brief. (DST changes are filtered out.)
            TravelSignal.checkNow()
            // Backfill the last 30 days of REAL per-day step totals from Apple Health on launch,
            // so the Progress average reflects full days — not the partial/missing history that
            // `importTodaySteps` alone left behind (it only ever captured "today so far").
            await refreshTrackerData(stepsDays: 30, days: 14)
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
                    // Re-pull the last 7 days (not just today) so yesterday gets finalized to
                    // its FULL total when she reopens the app the next day — the exact case
                    // where a day was frozen at a partial count. Tracker sleep/workouts/vitals
                    // re-pull too, so last night shows up by morning.
                    await refreshTrackerData(stepsDays: 7, days: 7)
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

    /// One serialized pass over both tracker pipes: Apple Health first, then the direct
    /// Google Health pipe — in that order, so Google's richer stage/vitals numbers win
    /// the per-day upsert on any overlapping day. Single-flight (see
    /// `trackerRefreshInFlight`); a caller that finds a pass in flight simply skips.
    private func refreshTrackerData(stepsDays: Int, days: Int) async {
        guard !trackerRefreshInFlight else { return }
        trackerRefreshInFlight = true
        defer { trackerRefreshInFlight = false }

        if HealthKitService.isAvailable {
            await HealthKitService.shared.importRecentSteps(days: stepsDays, into: context, existing: stepEntries)
            await HealthKitService.shared.importRecentSleep(days: days, into: context, existing: sleepEntries)
            await HealthKitService.shared.importRecentDetectedWorkouts(days: days, into: context, existing: detectedWorkouts)
            await HealthKitService.shared.importRecentVitals(days: days, into: context, existing: vitalsEntries)
        }
        if GoogleHealthSync.isConnected {
            // refresh() re-reads existing rows from the context itself — the imports
            // above may have just inserted rows the captured @Query arrays don't include.
            await GoogleHealthSync.refresh(days: days, into: context)
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
