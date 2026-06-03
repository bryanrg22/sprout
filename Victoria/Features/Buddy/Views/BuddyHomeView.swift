import SwiftUI
import SwiftData

/// The Buddy hub. Two faces:
///
/// - **Not linked yet** → a friendly "Pair with your buddy 💛" empty state that opens
///   `PairingView`.
/// - **Linked** → the SHARED panda at the top, a `BuddyStatusCard`, a row of nudge
///   buttons, and a peek at recent nudges (tap through to the full `NudgeInboxView`).
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
    @Query(sort: \WorkoutEntry.date) private var workouts: [WorkoutEntry]
    @Query private var profiles: [UserProfile]
    // Weigh-ins, for the OPT-IN full-stats share (weight trend + weekly rate). Read the same
    // way SettingsView/Dashboard do, so the trend the buddy sees matches what I see. Only
    // published when I've opted into sharing my full stats (see `publishMyState`).
    @Query(sort: \WeightEntry.date) private var weights: [WeightEntry]

    @State private var didAppear = false
    @State private var showPairing = false

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
    /// My consecutive-day logging streak (same shape as the dashboard's streak helper).
    private var myStreak: Int {
        let cal = Calendar.current
        let days = Set(allFood.map { cal.startOfDay(for: $0.date) })
            .union(water.map { cal.startOfDay(for: $0.date) })
            .union(steps.map { cal.startOfDay(for: $0.date) })
        var s = 0; var d = cal.startOfDay(for: .now)
        while days.contains(d) {
            s += 1
            guard let prev = cal.date(byAdding: .day, value: -1, to: d) else { break }
            d = prev
        }
        return s
    }

    // MARK: My SAFE activity + goals for the face-off (movement/hydration only)

    /// Did I get any movement in today? Exactly DashboardView's `workoutToday` read.
    private var myWorkedOutToday: Bool {
        workouts.contains { Calendar.current.isDateInToday($0.date) }
    }
    /// The single profile (Victoria), the way RootView resolves it.
    private var profile: UserProfile? { profiles.first }
    /// My own daily step goal (0 when there's no profile yet → face-off skips that bar).
    private var myStepGoal: Int { max(profile?.dailyStepGoal ?? 0, 0) }
    /// My own daily water goal in oz (0 when there's no profile yet).
    private var myWaterGoal: Double { max(profile?.waterTargetOz ?? 0, 0) }
    /// Which pixel avatar is me; the buddy's avatar defaults to the OTHER one in BuddyFaceOff.
    private var myAvatar: CompanionAvatar { profile?.companionAvatar ?? .victoria }

    // MARK: Friendly-rivalry prompts (kind, activity-only)

    /// My steps as a fraction of MY OWN goal (clamped 0...1), or `nil` if no goal is set —
    /// the SAME fair math the face-off uses, so the prompts and the bars never disagree.
    private var myStepFraction: Double? {
        guard myStepGoal > 0 else { return nil }
        return min(max(Double(todaySteps) / Double(myStepGoal), 0), 1)
    }
    /// Buddy's steps as a fraction of THEIR OWN goal (clamped 0...1), or `nil` if unknown.
    private var buddyStepFraction: Double? {
        guard let snap = model.buddySnapshot, snap.stepGoal > 0 else { return nil }
        return min(max(Double(snap.stepsToday) / Double(snap.stepGoal), 0), 1)
    }
    /// The (at most two) playful, kind prompts that apply right now, from my + buddy activity.
    private func challengePrompts(for snap: BuddySnapshotPayload) -> [BuddyChallengePrompt] {
        BuddyChallenges.prompts(
            myStepFraction: myStepFraction,
            theirStepFraction: buddyStepFraction,
            myWorkedOut: myWorkedOutToday,
            theirWorkedOut: snap.workedOutToday,
            myLoggedToday: myLoggedToday,
            theirLoggedToday: snap.loggedToday,
            buddyName: snap.displayName)
    }

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
            PairingView(model: model) {
                // On link, publish my real state right away so the panda + face-off are accurate.
                Task { await publishMyState() }
            }
        }
        .task {
            await model.refresh()
            // Keep my published presence + activity fresh whenever the hub opens.
            if model.isLinked {
                await publishMyState()
            }
            withAnimation { didAppear = true }
        }
        .refreshable { await model.refresh() }
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
                if model.isLinked { Task { await publishMyState() } }
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
    private func publishMyState() async {
        // Basis weight for target math — smoothed trend, else start weight, else a safe 150
        // (mirrors UserProfile.currentWeightLbs / SettingsView.currentWeightLbs).
        let basis = TrendCalculator.currentTrend(weights)
            ?? ((profile?.startWeightLbs ?? 0) > 0 ? profile!.startWeightLbs : 150)

        // Opt-in flag — gate everything below on it (nil profile → not sharing).
        let sharesFull = profile?.shareFullStatsWithBuddy ?? false
        // My real name, so the buddy sees "Bryan"/"Victoria" — never the literal "You".
        let myName = (profile?.name).flatMap { $0.isEmpty ? nil : $0 } ?? "Your buddy"

        await model.publishMine(
            loggedToday: myLoggedToday,
            dayStreak: myStreak,
            stepsToday: todaySteps,
            stepGoal: myStepGoal,
            waterToday: waterToday,
            waterGoal: myWaterGoal,
            workedOutToday: myWorkedOutToday,
            sharesFullData: sharesFull,
            trendWeightLbs: TrendCalculator.currentTrend(weights) ?? 0,
            goalWeightLbs: profile?.goalWeightLbs ?? 0,
            weeklyRateLbs: TrendCalculator.ratePerWeek(weights),    // SIGNED (negative = losing)
            caloriesEaten: todayFood.reduce(0) { $0 + $1.totalCalories },
            calorieTarget: profile.map { $0.dailyCalorieTarget(weightLbs: basis) } ?? 0,
            proteinEaten: todayFood.reduce(0) { $0 + $1.totalProteinG },
            proteinTarget: profile.map { $0.macroTargets(weightLbs: basis).proteinG } ?? 0,
            todayFoods: todayFood.map(\.name).filter { !$0.isEmpty }.prefix(8).joined(separator: ", "),
            displayName: myName
        )

        // Live buddy: if I just crossed a goal today, auto-cheer my buddy (once per goal per
        // day) — they get the existing nudge push, "🎉 Bryan just hit their calorie goal!"
        let milestoneInput = BuddyMilestoneInput(
            caloriesEaten: todayFood.reduce(0) { $0 + $1.totalCalories },
            calorieTarget: profile.map { $0.dailyCalorieTarget(weightLbs: basis) } ?? 0,
            proteinEaten: todayFood.reduce(0) { $0 + $1.totalProteinG },
            proteinTarget: profile.map { $0.macroTargets(weightLbs: basis).proteinG } ?? 0,
            steps: todaySteps,
            stepGoal: myStepGoal,
            waterOz: waterToday,
            waterGoal: myWaterGoal,
            dayStreak: myStreak
        )
        let fresh = BuddyMilestones.consumeNewlyReached(milestoneInput, myUserID: model.myUserID)
        await model.celebrate(fresh, myName: myName)
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
        if let snap = model.buddySnapshot {
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
                myAvatar: myAvatar,
                buddy: snap
            )
            .appearLift(didAppear, index: 3)

            // (c2) Playful, KIND friendly-rivalry prompts derived from our SAFE activity
            // ("Bryan hit the gym — your turn?", "you're winning the step race"). Each just
            // sends a warm, encouraging note to the buddy — never guilt, never raw numbers.
            // (Renders nothing — and reserves no space — when no prompt applies.)
            challengeSection(for: snap)
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
    }

    /// The playful, KIND friendly-rivalry prompt(s) for the current activity, in an elevated
    /// card. Renders nothing when there's nothing to prompt (so it never shows an empty box).
    @ViewBuilder
    private func challengeSection(for snap: BuddySnapshotPayload) -> some View {
        let prompts = challengePrompts(for: snap)
        if !prompts.isEmpty {
            VStack(alignment: .leading, spacing: Theme.Space.sm) {
                Text("Today's friendly nudge")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                ForEach(prompts) { prompt in
                    BuddyChallengeCard(prompt: prompt) { message, kind in
                        Task { await model.send(text: message, kind: kind) }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardElevated()
            .appearLift(didAppear, index: 4)
        }
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
                             logged: model.buddySnapshot?.loggedToday ?? false))
        }
        .cardElevated(padding: Theme.Space.lg)
    }

    /// My buddy's pixel character is the OTHER avatar (if I'm Victoria, they're Bryan).
    private var theirAvatar: CompanionAvatar { myAvatar == .victoria ? .bryan : .victoria }

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
                Text("Team up with a friend to keep each other going. You'll grow a little panda together and send each other cheers — never any pressure, and never your numbers.")
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
                          WorkoutEntry.self, WeightEntry.self, UserProfile.self], inMemory: true)
}
