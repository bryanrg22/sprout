import SwiftUI
import SwiftData

/// The Buddy hub. Two faces:
///
/// - **Not linked yet** → a friendly "Pair with your buddy 💛" empty state that opens
///   `PairingView`.
/// - **Linked** → the SHARED panda at the top, the buddy's day (or, when it is days old,
///   a card that says so and offers to unpair), a row of nudge buttons, and a peek at
///   recent nudges. Unpairing is in the toolbar menu, behind a confirmation.
///
/// All sync runs through `BuddyViewModel` in `Task {}`; `BuddySyncError`s surface as kind
/// inline banners — nothing here can crash or shame.
struct BuddyHomeView: View {
    /// Owned here so the whole Buddy flow shares one service + state. The single Dashboard
    /// entry point pushes this view, which constructs the VM (persisting "buddyMyUserID").
    @State private var model = BuddyViewModel()

    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase

    // Read MY own "did I log today?" the SAME way the dashboard does, so the shared
    // panda reflects my real activity (see DashboardView.insightInput.loggedAnythingToday).
    @Query(sort: \FoodEntry.date) private var allFood: [FoodEntry]
    @Query private var water: [WaterEntry]
    @Query(sort: \StepsEntry.date) private var steps: [StepsEntry]
    // For the FAIR face-off we also need my SAFE activity + MY OWN goals. Workouts give the
    // "moved today" flag (same read as DashboardView.workoutToday); the profile supplies my
    // step/water goals + which pixel avatar is me. Read with @Query the way RootView fetches
    // the single profile — BuddyHomeView() takes no args, so this stays self-contained.
    // Reads `WorkoutSession` — the model the shipping Workouts tab actually writes. (The legacy
    // `WorkoutEntry` is only written by a debug-only screen, so a real gym session never set this
    // flag and the face-off "Exercise" row stayed "Not yet" even after a logged workout.)
    @Query(sort: \WorkoutSession.date) private var workouts: [WorkoutSession]
    /// Tracker-detected workouts: they make a day active in the weekly competition.
    @Query(sort: \DetectedWorkout.date) private var detectedWorkouts: [DetectedWorkout]
    @Query private var profiles: [UserProfile]
    // Weigh-ins, for the OPT-IN full-stats share (weight trend + weekly rate). Read the same
    // way SettingsView/Dashboard do, so the trend the buddy sees matches what I see. Only
    // published when I've opted into sharing my full stats (see `publishMyState`).
    @Query(sort: \WeightEntry.date) private var weights: [WeightEntry]

    @State private var didAppear = false
    @State private var showPairing = false
    @State private var confirmUnpair = false

    // MARK: My activity (mirrors DashboardView)

    private var todayFood: [FoodEntry] {
        allFood.filter { Calendar.current.isDateInToday($0.date) }
    }
    private var waterToday: Double {
        water.filter { Calendar.current.isDateInToday($0.date) }.reduce(0) { $0 + $1.amountOz }
    }
    private var todaySteps: Int {
        steps.first { Calendar.current.isDateInToday($0.date) }?.count ?? 0
    }
    /// Exactly the dashboard's definition of "I showed up today".
    private var myLoggedToday: Bool {
        !todayFood.isEmpty || waterToday > 0 || todaySteps > 0
    }
    /// My consecutive-day logging streak — the SHARED calculator (food / water / manual weigh-ins
    /// only). Must NOT count auto-imported steps, or the buddy sees an inflated streak and gets a
    /// false "hit a 30-day streak!" cheer — the exact bug `StreakCalculator` was created to fix.
    private var myStreak: Int {
        StreakCalculator.loggingStreak(foods: allFood, waters: water, weights: weights)
    }

    // MARK: My SAFE activity + goals for the face-off (movement/hydration only)

    /// Did I get any movement in today? Exactly DashboardView's `workoutToday` read.
    private var myWorkedOutToday: Bool {
        workouts.contains { Calendar.current.isDateInToday($0.date) }
    }
    /// The single profile, the way RootView resolves it.
    private var profile: UserProfile? { UserProfile.primary(of: profiles) }
    /// My own daily step goal (0 when there's no profile yet → face-off skips that bar).
    private var myStepGoal: Int { max(profile?.dailyStepGoal ?? 0, 0) }
    /// My own daily water goal in oz (0 when there's no profile yet).
    private var myWaterGoal: Double { max(profile?.waterTargetOz ?? 0, 0) }
    /// Which pixel avatar is me; the buddy's avatar defaults to the OTHER one in BuddyFaceOff.
    private var myAvatar: CompanionAvatar { profile?.companionAvatar ?? .victoria }

    // MARK: Friendly-rivalry prompts (kind, activity-only)

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.Space.md) {
                if model.isLinked {
                    linkedContent
                } else {
                    emptyState
                }
            }
            .padding(.horizontal)
            .padding(.top, Theme.Space.xs)
            .padding(.bottom, 40)
        }
        .scrollIndicators(.hidden)
        .background(backdrop)
        .navigationTitle("Buddy")
        .navigationBarTitleDisplayMode(.large)
        .overlay(alignment: .top) { ConfettiBurst(trigger: model.sendConfetti) }
        .safeAreaInset(edge: .bottom) {
            if let banner = model.banner {
                BuddyBannerView(banner: banner) { model.banner = nil }
                    .padding(.horizontal)
                    .padding(.bottom, Theme.Space.sm)
            }
        }
        .navigationDestination(isPresented: $showPairing) {
            PairingView(model: model, sharesFullStats: profile?.shareFullStatsWithBuddy ?? false) {
                // On link, publish my real state right away so the panda + face-off are accurate.
                Task { await publishMyState() }
            }
        }
        .toolbar {
            if model.isLinked {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button(role: .destructive) { confirmUnpair = true } label: {
                            Label("Unpair from \(buddyName)", systemImage: "person.2.slash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .accessibilityLabel("Buddy options")
                    }
                }
            }
        }
        // Ending a pairing cannot be undone from here (pairing again takes a new code from
        // one of the two), so it is asked once more, with what it does. An alert, not a
        // confirmation dialog: on iOS 26 that is a popover with the cancel button left out,
        // anchored wherever the modifier sits; both choices belong on screen here.
        .alert("Unpair from \(buddyName)?", isPresented: $confirmUnpair) {
            Button("Unpair", role: .destructive) { Task { await model.unpair() } }
            Button("Stay paired", role: .cancel) {}
        } message: {
            Text("You two will stop seeing each other's day and notes, and the day you shared is removed from iCloud. Everything you logged stays on your phone. To pair again, one of you types the other's new code.")
        }
        .task {
            await model.refresh()
            // Keep my published presence + activity fresh whenever the hub opens.
            await publishMyState()
            withAnimation { didAppear = true }
            #if DEBUG
            // DEBUG: `--demo-buddy-ui unpair` opens the confirmation, `unpair-confirmed` does
            // what its Unpair button does, `pairing-…` opens the pairing screen in a failed
            // state, so each can be looked at without tapping.
            switch BuddyDemoUI.requested {
            case .unpair? where model.isLinked: confirmUnpair = true
            case .unpairConfirmed?:             await model.unpair()
            case .pairing?:                    showPairing = !model.isLinked
            default:                           break
            }
            #endif
        }
        .refreshable { await model.refresh() }
        // While the hub is OPEN, re-pull my buddy's snapshot every ~20s. CloudKit's public-DB
        // query-subscription push is unreliable (and at best only wakes a backgrounded app), so
        // without this a buddy's update wouldn't appear while you're sitting on the page — exactly
        // the "she's been on the buddy page and it still isn't updating" report. Auto-cancels when
        // the view disappears.
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(20))
                if Task.isCancelled { break }
                if model.isLinked { await model.refresh() }
            }
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                // Coming back: pull my buddy's latest, and if a NEW DAY has begun, republish
                // my fresh "today" state (totals reset, goal-celebrations re-armed) right away.
                if model.isLinked {
                    Task {
                        await model.refresh()
                        if BuddyDay.rolledOver() {
                            Diagnostics.shared.log("buddy: new day — republishing fresh state", .sync)
                            await publishMyState()
                        }
                    }
                }
            case .background:
                // Leaving: publish my latest AND auto-cheer any goal I just crossed — so the
                // ping fires when I set the phone down, not only when I open the Buddy tab.
                Task { await publishMyState() }
            default:
                break
            }
        }
    }

    /// Publish my presence AND my SAFE daily activity (steps / water / movement) with MY OWN
    /// goals, so the buddy's hub can show a fair face-off. One place so both the on-appear
    /// refresh and the just-linked warm-up stay in sync.
    ///
    /// **Full stats (opt-in).** If I've turned on `shareFullStatsWithBuddy`, I ALSO publish
    /// the full daily picture — my weight trend + weekly rate, calorie + protein progress,
    /// and today's food names — computed here from the same @Query data the dashboard and
    /// Settings use (so the buddy sees exactly what I see). When the toggle is off,
    /// `sharesFullData` is false and the full-data values stay at 0/"" (the publish path
    /// sends nothing meaningful, and the buddy's card hides itself). A nil profile degrades
    /// gracefully to "not sharing".
    /// My competition record, computed exactly as it is published (the same composer).
    private var myCompetition: CompetitionRecord {
        CompetitionRecord.decode(BuddyStateComposer.compose(
            profile: profile, foods: allFood, water: water, steps: steps, sessions: workouts,
            weights: weights, detected: detectedWorkouts).competitionWeeks)
    }

    private func publishMyState() async {
        // One source of truth for the snapshot (shared with the always-on `BuddyAutoPublisher`).
        let s = BuddyStateComposer.compose(profile: profile, foods: allFood, water: water,
                                           steps: steps, sessions: workouts, weights: weights,
                                           detected: detectedWorkouts)
        // Publishes only while linked, then cheers the buddy for any goal just crossed.
        await model.publishIfLinked(s)
    }

    // MARK: - Linked content

    @ViewBuilder
    private var linkedContent: some View {
        // (a) Shared character.
        sharedPandaCard.appearLift(didAppear, index: 0)

        // (b) Buddy's whole day in ONE widget — warm status (avatar, mood, streak, presence)
        // PLUS, when they've opted into sharing, their metrics as home-screen tiles (weight +
        // calorie/protein rings) and today's food as chips. Replaces the old status +
        // full-stats pair. Metrics self-hide when the buddy shares activity only.
        if case .stale(let since, let days) = model.buddyFreshness {
            // Days without a publish: say so instead of showing old numbers as today's.
            BuddyStaleCard(name: buddyName, nameAtStart: model.buddyFirstNameCapitalized,
                           since: since, days: days) { confirmUnpair = true }
                .appearLift(didAppear, index: 1)
        } else if model.buddySnapshot == nil, model.lastBuddyFetchAt != nil {
            // Fetched, and there is nothing yet: the buddy has never published.
            BuddyWaitingCard(name: model.buddyFirstNameCapitalized).appearLift(didAppear, index: 1)
        } else if let snap = model.buddySnapshot {
            BuddyDayCard(snapshot: snap, avatar: theirAvatar).appearLift(didAppear, index: 1)

            // (c) Playful, FAIR, SAFE activity face-off — both pixel avatars + a per-metric
            // (steps/water/gym) comparison scored as % of each person's OWN goal. An
            // ADDITION beneath the shared panda + status card; the panda + nudges stay intact.
            BuddyFaceOff(
                mySteps: todaySteps,
                myStepGoal: myStepGoal,
                myWaterOz: waterToday,
                myWaterGoal: myWaterGoal,
                myWorkedOut: myWorkedOutToday,
                myWorkoutSummary: BuddyStateComposer.workoutSummary(workouts),
                myAvatar: myAvatar,
                buddy: snap
            )
            .appearLift(didAppear, index: 3)

            // (c2) The weekly competition: points for days inside each person's own ranges.
            CompetitionCard(mine: myCompetition,
                            theirs: CompetitionRecord.decode(snap.competitionWeeks),
                            myName: "You", buddyName: model.buddyFirstNameCapitalized)
                .appearLift(didAppear, index: 4)
        }

        // (d) Nudge buttons + write-your-own composer.
        NudgeButtonsRow(
            onSend: { kind in Task { await model.send(kind) } },
            onSendCustom: { text in Task { await model.send(text: text) } },
            lastSentKind: model.lastSentKind
        )
        .cardElevated()
        .appearLift(didAppear, index: 5)

        // (e) Recent nudges.
        recentNudges.appearLift(didAppear, index: 6)

        // (f) Sync health, in plain words. Two silent failure modes used to be invisible:
        // MY publishes quietly failing (buddy sees a frozen me) and THEIR device not
        // uploading (I see a frozen them). One honest little footer surfaces both.
        syncStatusFooter.appearLift(didAppear, index: 7)
    }

    /// A quiet footer that tells the truth about sync: when my day last reached iCloud
    /// (with a soft warning if the last attempt failed), and how old the buddy's data is
    /// when it's stale enough to mislead (> a day). Caption-sized — informative, not scary.
    @ViewBuilder
    private var syncStatusFooter: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let problem = model.accountProblem {
                // Signed out of iCloud: nothing syncs until that changes, so it is said plainly.
                Label(problem, systemImage: "person.icloud")
                    .foregroundStyle(Theme.warning)
            } else if model.lastPublishFailed {
                Label("Your last update hasn't reached iCloud yet — it'll retry on its own.",
                      systemImage: "icloud.slash")
                    .foregroundStyle(Theme.warning)
            } else if let t = model.lastPublishAt {
                Label("You shared your day \(Self.relative(t)).", systemImage: "icloud.and.arrow.up")
                    .foregroundStyle(Theme.textSecondary)
            }
            // A day or two without an update (three or more is the stale card above).
            if case .quiet(let since, _) = model.buddyFreshness {
                Label("\(model.buddyFirstNameCapitalized)'s last update was \(Self.relative(since)), so what you see is from then. It refreshes when they next open Sprout.",
                      systemImage: "clock.arrow.circlepath")
                    .foregroundStyle(Theme.warning)
            }
        }
        .font(.caption)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Theme.Space.xs)
    }

    private static func relative(_ date: Date) -> String {
        if Date.now.timeIntervalSince(date) < 90 { return "just now" }
        let fmt = RelativeDateTimeFormatter()
        fmt.unitsStyle = .short
        return fmt.localizedString(for: date, relativeTo: .now)
    }

    /// The shared panda inside an elevated card, with a header. Passes BOTH contributors so
    /// the card shows you + your buddy flanking the panda — making it clear it takes both of
    /// you to keep it thriving.
    private var sharedPandaCard: some View {
        VStack(spacing: Theme.Space.sm) {
            HStack {
                Text("Your shared panda")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.textSecondary)
                Spacer()
            }
            SharedPandaPlaceholder(
                state: model.sharedState(myLoggedToday: myLoggedToday),
                me: .init(avatar: myAvatar, name: "You", logged: myLoggedToday),
                buddy: .init(avatar: theirAvatar,
                             name: model.buddySnapshot?.displayName ?? "Buddy",
                             logged: model.buddySnapshot?.loggedTodayEffective ?? false))
        }
        .cardElevated(padding: Theme.Space.lg)
    }

    /// My buddy's pixel character is the other built-in avatar from mine.
    private var theirAvatar: CompanionAvatar { myAvatar.buddyStandIn }

    /// The buddy's first name for titles and buttons ("Sam"), or "your buddy" before they
    /// have published one.
    private var buddyName: String { model.buddyFirstName }

    /// A peek at the latest few notes; taps through to the full inbox.
    private var recentNudges: some View {
        VStack(alignment: .leading, spacing: Theme.Space.sm) {
            HStack {
                Text("Recent notes")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                if model.unreadCount > 0 {
                    Text("\(model.unreadCount)")
                        .font(.caption2.weight(.bold)).monospacedDigit()
                        .padding(.horizontal, 7).padding(.vertical, 2)
                        .background(Theme.brand, in: Capsule())
                        .foregroundStyle(Color.black)
                }
                Spacer()
                NavigationLink {
                    NudgeInboxView(model: model)
                } label: {
                    Text("See all")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.brand)
                }
            }

            if model.inbox.isEmpty {
                HStack(spacing: Theme.Space.sm) {
                    Image(systemName: "tray")
                        .font(.title3)
                        .foregroundStyle(Theme.textSecondary)
                        .frame(width: 44, height: 44)
                        .background(Theme.brandSoft, in: RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous))
                    Text("No notes yet — send the first cheer above! 💛")
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 2)
            } else {
                ForEach(model.inbox.prefix(3)) { nudge in
                    NudgeCard(nudge: nudge)
                }
            }
        }
    }

    // MARK: - Empty state (not linked)

    private var emptyState: some View {
        VStack(spacing: Theme.Space.lg) {
            SharedPandaPlaceholder(state: .sleepy)
                .padding(.top, Theme.Space.md)

            VStack(spacing: Theme.Space.sm) {
                Text("Pair with your buddy 💛")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(Theme.textPrimary)
                    .multilineTextAlignment(.center)
                Text("Team up with a friend to keep each other going. You'll grow a little panda together and send each other cheers, with never any pressure. What your buddy sees of your numbers is your choice in Settings.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, Theme.Space.sm)
            }

            Button { showPairing = true } label: {
                Label("Pair with a buddy", systemImage: "person.2.fill")
            }
            .buttonStyle(.primary)
        }
        .frame(maxWidth: .infinity)
        .cardElevated(padding: Theme.Space.lg)
        .padding(.top, Theme.Space.lg)
        .appearLift(didAppear, index: 0)
    }

    // MARK: - Backdrop

    private var backdrop: some View {
        Theme.background
            .overlay(alignment: .top) {
                RadialGradient(colors: [Theme.brand.opacity(0.10), .clear],
                               center: .top, startRadius: 0, endRadius: 380)
                    .frame(height: 420)
                    .frame(maxWidth: .infinity, alignment: .top)
                    .allowsHitTesting(false)
            }
            .ignoresSafeArea()
    }
}

#Preview("Buddy home") {
    NavigationStack {
        BuddyHomeView()
    }
    .modelContainer(for: [FoodEntry.self, WaterEntry.self, StepsEntry.self,
                          WorkoutSession.self, WeightEntry.self, UserProfile.self], inMemory: true)
}
