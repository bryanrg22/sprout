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
        // A `--ui-testing` launch runs on an in-memory store that must look the same every
        // run: nothing is imported from the simulator's Apple Health or a connected tracker.
        guard !UITestHooks.isActive else { return }
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
    @State private var selection = HomeTab.initial(arguments: CommandLine.arguments).rawValue
    /// Home or Gym. Stored, so the app reopens where it was left; `ModeSwitch` writes the same key.
    @AppStorage(AppMode.storageKey) private var storedMode: String = AppMode.home.rawValue
    private var mode: AppMode { AppMode.resolve(stored: storedMode) }
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
        // Both surfaces stay alive under the switch, so each keeps its scroll position, its
        // navigation path and any half-typed text while the other is showing.
        ZStack {
            TabView(selection: $selection) {
                DashboardView(profile: profile)
                    .tabItem { Label("Today", systemImage: "house.fill").accessibilityIdentifier(AccessibilityID.Tab.today) }.tag(HomeTab.today.rawValue)

                FoodLogView(profile: profile)
                    .tabItem { Label("Nutrients", systemImage: "fork.knife").accessibilityIdentifier(AccessibilityID.Tab.nutrients) }.tag(HomeTab.nutrients.rawValue)

                WeightView(profile: profile)
                    .tabItem { Label("Progress", systemImage: "chart.line.uptrend.xyaxis").accessibilityIdentifier(AccessibilityID.Tab.progress) }.tag(HomeTab.progress.rawValue)

                CoachView(profile: profile)
                    .tabItem { Label(profile.coachName, systemImage: "sparkles").accessibilityIdentifier(AccessibilityID.Tab.coach) }.tag(HomeTab.coach.rawValue)
            }
            .opacity(mode == .home ? 1 : 0)
            .allowsHitTesting(mode == .home)
            .accessibilityHidden(mode != .home)

            WorkoutsView()
                .opacity(mode == .gym ? 1 : 0)
                .allowsHitTesting(mode == .gym)
                .accessibilityHidden(mode != .gym)
        }
        .onAppear {
            // A demo launch can ask for Gym; otherwise the stored choice stands.
            let initial = AppMode.initial(arguments: CommandLine.arguments, stored: storedMode)
            if initial.rawValue != storedMode { storedMode = initial.rawValue }
        }
        .environment(askVita)
        // Keep my buddy snapshot fresh app-wide — publish the moment I log on ANY tab (debounced) and
        // when the app backgrounds, not only while the Buddy page is open. (See `BuddyAutoPublisher`.)
        .background(BuddyAutoPublisher())
        // Home's bar is Today · Nutrients · Progress · Vita; workouts are the Gym surface, reached
        // by the Home | Gym switch. Buddy is a Dashboard quick-link.
        // When a long-press asks Vita about something, jump to her tab so she can answer.
        .onChange(of: askVita.pendingTopic) { _, topic in
            if topic != nil {
                // The coach lives in Home: a question asked from Gym switches surface too.
                let destination = AppMode.destinationForCoach()
                storedMode = destination.mode.rawValue
                selection = destination.homeTab.rawValue
            }
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
        let next = PlanTargetSync.overrides(
            plan: plan.map { .init(hasRange: $0.hasRange, calorieMin: $0.calorieMin,
                                   calorieMax: $0.calorieMax, proteinTarget: $0.proteinTarget) },
            currentProtein: profile.proteinTargetOverride)
        if profile.calorieTargetOverride != next.calorie { profile.calorieTargetOverride = next.calorie }
        if profile.calorieMaxOverride != next.calorieMax { profile.calorieMaxOverride = next.calorieMax }
        if profile.proteinTargetOverride != next.protein { profile.proteinTargetOverride = next.protein }
    }
}
