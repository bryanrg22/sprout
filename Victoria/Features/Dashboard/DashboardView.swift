import SwiftUI
import SwiftData
import Charts

/// "Today" — the warm, encouraging home. Hero = calories remaining (a budget she
/// can spend), an Activity row (steps + water), macros, the smoothed weight trend,
/// and a coach line. Steps from Health can top up her calorie budget when enabled.
struct DashboardView: View {
    @Bindable var profile: UserProfile
    @Environment(\.modelContext) private var context

    @Query(sort: \FoodEntry.date) private var allFood: [FoodEntry]
    @Query(sort: \WeightEntry.date) private var weights: [WeightEntry]
    @Query private var water: [WaterEntry]
    @Query(sort: \StepsEntry.date) private var steps: [StepsEntry]
    @Query(sort: \WorkoutEntry.date) private var workouts: [WorkoutEntry]

    /// Bumped on each water log so `.sensoryFeedback` fires a success tap.
    @State private var waterPulse = 0
    /// Drives the one-time entrance reveal of the hero ring.
    @State private var didAppear = false
    /// Presents Settings (opened from the pixel-avatar button in the header).
    @State private var showSettings = false

    // MARK: Derived
    private var todayFood: [FoodEntry] { allFood.filter { Calendar.current.isDateInToday($0.date) } }
    private var consumed: Double { todayFood.reduce(0) { $0 + $1.totalCalories } }
    private var protein: Double { todayFood.reduce(0) { $0 + $1.totalProteinG } }
    private var carbs: Double { todayFood.reduce(0) { $0 + $1.totalCarbsG } }
    private var fat: Double { todayFood.reduce(0) { $0 + $1.totalFatG } }

    private var trendWeight: Double? { TrendCalculator.currentTrend(weights) }
    private var basisWeight: Double { trendWeight ?? (profile.startWeightLbs > 0 ? profile.startWeightLbs : 150) }

    private var todaySteps: Int { steps.first { Calendar.current.isDateInToday($0.date) }?.count ?? 0 }
    private var baseTarget: Double { profile.dailyCalorieTarget(weightLbs: basisWeight) }
    /// Returns 0 unless `profile.stepsAdjustCalories` is on (default: off → steps are display-only).
    private var stepBonus: Double { profile.stepBonusCalories(weightLbs: basisWeight, steps: todaySteps) }
    private var target: Double { baseTarget + stepBonus }
    private var remaining: Double { target - consumed }
    private var ringProgress: Double { target > 0 ? consumed / target : 0 }
    /// She's reached her fuel target for the day (within a small grace band). Shown as
    /// a win, not "budget gone" — the anti-restriction framing for an under-eater.
    private var reachedFuel: Bool { target > 0 && consumed >= target * 0.97 }
    private var macros: NutritionMath.Macros { profile.macroTargets(weightLbs: basisWeight) }
    private var waterToday: Double { water.filter { Calendar.current.isDateInToday($0.date) }.reduce(0) { $0 + $1.amountOz } }
    private var workoutToday: Bool { workouts.contains { Calendar.current.isDateInToday($0.date) } }

    /// Snapshot handed to the free on-device insight engine. Streak fields use
    /// multi-day helpers below; single-day wins read straight off today's totals.
    private var insightInput: DailyInsightEngine.Input {
        DailyInsightEngine.Input(
            caloriesEaten: consumed,
            calorieTarget: target,
            protein: protein,
            proteinTarget: macros.proteinG,
            waterOz: waterToday,
            waterGoalOz: profile.waterTargetOz,
            steps: todaySteps,
            stepGoal: profile.dailyStepGoal,
            loggedAnythingToday: !todayFood.isEmpty || waterToday > 0 || todaySteps > 0,
            loggingStreakDays: streak,
            proteinHitStreakDays: hitStreak { dayProtein($0) >= macros.proteinG && macros.proteinG > 0 },
            hydrationHitStreakDays: hitStreak { dayWater($0) >= profile.waterTargetOz && profile.waterTargetOz > 0 },
            workoutToday: workoutToday,
            hourOfDay: Calendar.current.component(.hour, from: .now)
        )
    }

    // Per-day totals used for the streak helpers.
    private func dayProtein(_ day: Date) -> Double {
        allFood.filter { Calendar.current.isDate($0.date, inSameDayAs: day) }.reduce(0) { $0 + $1.totalProteinG }
    }
    private func dayWater(_ day: Date) -> Double {
        water.filter { Calendar.current.isDate($0.date, inSameDayAs: day) }.reduce(0) { $0 + $1.amountOz }
    }
    /// Counts consecutive days back from today where `met(day)` is true.
    private func hitStreak(_ met: (Date) -> Bool) -> Int {
        let cal = Calendar.current
        var n = 0
        var day = cal.startOfDay(for: .now)
        while met(day) {
            n += 1
            guard let prev = cal.date(byAdding: .day, value: -1, to: day) else { break }
            day = prev
        }
        return n
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Theme.Space.md) {
                    header.appearLift(didAppear, index: 0)
                    // Recoverable "add your key" nudge — only when she skipped it in setup.
                    FinishSetupCard(coachName: profile.coachName.isEmpty ? "Vita" : profile.coachName)
                        .appearLift(didAppear, index: 1)
                    // (Removed the "Vita noticed" InsightCard — it stacked with the weekly reflection
                    // and the streak header, over-cluttering the top of Today.)
                    // Earned, one-time "add a widget" nudge — only once she's a couple days in.
                    WidgetPromoCard(profile: profile, eligible: streak >= 2)
                        .appearLift(didAppear, index: 2)
                    WeeklyReflectionCard(profile: profile).appearLift(didAppear, index: 2)
                    RecommendationCard(profile: profile).appearLift(didAppear, index: 3)
                    caloriesHero
                        .askVita {
                            AskVitaTopic(
                                name: "Calories",
                                icon: "flame.fill",
                                value: reachedFuel ? "Fueled for today 🎉"
                                                   : "\(Int(max(remaining, 0).rounded())) kcal to go",
                                question: "What does my 'calories to go' number actually mean — and in real terms, what happens if I go over it, or under it, on a given day?")
                        }
                        .appearLift(didAppear, index: 4)
                    CompanionCard(profile: profile, caloriesEaten: consumed,
                                  protein: protein, waterOz: waterToday)
                        .askVita {
                            AskVitaTopic(
                                name: "\(profile.coachName.isEmpty ? "Your companion" : profile.coachName) the companion",
                                icon: "sparkles",
                                value: "Reacts to your day 💚",
                                question: "What makes my little companion happy, and what is it really telling me about how my day is going?")
                        }
                        .appearLift(didAppear, index: 5)
                    buddyCard.appearLift(didAppear, index: 6)
                    activityRow
                        .askVita {
                            AskVitaTopic(
                                name: "Steps & activity",
                                icon: "figure.walk",
                                value: "\(todaySteps.formatted()) of \(stepGoal.formatted()) steps",
                                question: "How do my steps actually affect my weight-loss progress — and what's the real impact if I don't hit my step goal on some days?")
                        }
                        .appearLift(didAppear, index: 6)
                    macrosCard.appearLift(didAppear, index: 7)
                    ChecklistCard(profile: profile).appearLift(didAppear, index: 8)
                    quickLinks.appearLift(didAppear, index: 9)
                    // Weight trend + the streak "proud of you" line moved OFF Home: Home is the daily
                    // essentials. Weight lives on Progress; the streak already shows in the header flame.
                }
                .padding(.horizontal)
                .padding(.top, Theme.Space.xs)
                .padding(.bottom, 40)
            }
            .scrollIndicators(.hidden)
            .background(backdrop)
            .toolbar(.hidden, for: .navigationBar)
            .sensoryFeedback(.success, trigger: waterPulse)
            .sheet(isPresented: $showSettings) { SettingsView(profile: profile) }
            .onAppear {
                guard !didAppear else { return }
                // Plain flip — each element supplies its own entrance curve
                // (cards cascade via .appearLift, rings sweep, numbers count up).
                // A tiny delay lets the first frame settle so the reveal reads.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    didAppear = true
                }
            }
        }
    }

    /// Buddy lives here — a prominent full-width card right under Sprout (above Steps/Water),
    /// fronted by the shared pixel panda, instead of a small tile buried at the bottom.
    private var buddyCard: some View {
        NavigationLink {
            BuddyHomeView()
        } label: {
            HStack(spacing: Theme.Space.md) {
                PixelArtView(rows: PixelPanda.rows(mood: .okay), palette: PixelPanda.palette)
                    .frame(width: 38, height: 38)
                    .padding(7)
                    .background(Theme.info.opacity(0.15),
                                in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                VStack(alignment: .leading, spacing: 1) {
                    Text("Buddy")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Text("Cheer each other on 💛")
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Theme.textSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardElevated()
        }
        .buttonStyle(.plain)
    }

    /// Quick links to the secondary screens that don't have their own tab.
    private var quickLinks: some View {
        // Buddy moved up to its own card under Sprout. Achievements stays here as a full-width
        // tile (no tab of its own — 5-tab max keeps Vita on the bar).
        NavigationLink {
            AchievementsView(profile: profile)
        } label: {
            quickLinkTile(title: "Achievements", icon: "trophy.fill", tint: Theme.warning)
        }
        .buttonStyle(.plain)
    }

    private func quickLinkTile(title: String, icon: String, tint: Color) -> some View {
        HStack(spacing: Theme.Space.sm) {
            Image(systemName: icon)
                .font(.headline)
                .foregroundStyle(tint)
                .frame(width: 34, height: 34)
                .background(tint.opacity(0.15), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1).minimumScaleFactor(0.6)   // fit "Achievements" without the "Achievem…" cut
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardElevated()
    }

    /// Near-black canvas with a soft lime glow bleeding down from the top behind the hero.
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

    // MARK: Header
    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 3) {
                Text(greetingText)
                    .font(.largeTitle.weight(.bold))
                    .minimumScaleFactor(0.7)
                    .lineLimit(2)
                Text(Date.now, format: .dateTime.weekday(.wide).month().day())
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Theme.textSecondary)
                    .textCase(.uppercase)
                    .tracking(0.5)
            }
            Spacer(minLength: Theme.Space.sm)
            if streak > 0 { streakPill }
            pfpButton
        }
        .padding(.top, Theme.Space.sm)
    }

    /// Top-right pixel-avatar that opens Settings (Gmail-style account button).
    private var pfpButton: some View {
        Button { showSettings = true } label: { avatarThumb }
            .buttonStyle(.plain)
            .bouncyPress()
            .accessibilityLabel("Settings")
    }

    private var avatarThumb: some View {
        Group {
            switch profile.companionAvatar {
            case .bryan:    PixelArtView(rows: PixelBryan.rows(mood: .happy, eyesOpen: true), palette: PixelBryan.palette)
            case .victoria: PixelArtView(rows: PixelVictoria.rows(mood: .happy, eyesOpen: true), palette: PixelVictoria.palette)
            }
        }
        .frame(width: 30, height: 36)
        .frame(width: 46, height: 46)
        .background(Theme.brandSoft, in: Circle())
        .overlay(Circle().strokeBorder(Theme.divider, lineWidth: 1))
        .clipShape(Circle())
    }

    private var streakPill: some View {
        HStack(spacing: 5) {
            Image(systemName: "flame.fill")
            Text("\(streak)").fontWeight(.heavy).monospacedDigit()
                .contentTransition(.numericText())
        }
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(Theme.warning)
        .padding(.horizontal, 13).padding(.vertical, 8)
        .background(Theme.warning.opacity(0.15), in: Capsule())
        .overlay(Capsule().strokeBorder(Theme.warning.opacity(0.30), lineWidth: 1))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(streak) day streak")
    }

    private var greetingText: String {
        let h = Calendar.current.component(.hour, from: .now)
        let part = h < 12 ? "Good morning" : (h < 18 ? "Good afternoon" : "Good evening")
        return "\(part),\n\(profile.currentDisplayName.capitalized)"
    }

    // MARK: Calories hero
    private var caloriesHero: some View {
        HStack(spacing: Theme.Space.lg) {
            CalorieSpeedometer(progress: didAppear ? ringProgress : 0,
                               gradient: .brandSweep) {
                VStack(spacing: 0) {
                    // For an under-eater we frame the goal as fuel to REACH, not a budget
                    // to drain. Still room to eat → "TO GO" (encouraging). Reached the
                    // target → a celebratory "Fueled!" check, not "0 left". A little over
                    // is gently neutral, never alarming.
                    if reachedFuel {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 40, weight: .bold))
                            .foregroundStyle(Theme.positive)
                            .popIn(didAppear)
                        Text("Fueled!")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Theme.positive)
                            .textCase(.uppercase).tracking(0.5)
                    } else {
                        CountUpText(value: max(remaining, 0), isActive: didAppear) {
                            "\(Int($0.rounded()))"
                        }
                            .font(.system(size: 44, weight: .heavy, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(Theme.textPrimary)
                            .minimumScaleFactor(0.6)
                            .lineLimit(1)
                            .animation(.easeOut(duration: 1.0), value: didAppear)
                        Text("kcal to go")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(Theme.textSecondary)
                            .textCase(.uppercase)
                            .tracking(0.5)
                    }
                }
            }
            .animation(.spring(response: 0.5, dampingFraction: 0.85), value: ringProgress)

            VStack(alignment: .leading, spacing: 11) {
                heroRow("Goal", Int(target.rounded()), Theme.brand)
                heroRow("Eaten", Int(consumed.rounded()), Theme.textSecondary)
                Divider().overlay(Theme.divider)
                // Once fueled, a remaining number ("26 to go") contradicts "Reached",
                // so we celebrate with a checkmark instead — and it gracefully avoids
                // showing an "over" number if she's eaten a little past the goal.
                if reachedFuel {
                    heroRow("Reached 🎉", "✓", Theme.positive)
                } else {
                    heroRow("To go", Int(max(remaining, 0).rounded()), Theme.brand)
                }
                if stepBonus > 0 {
                    HStack(spacing: 5) {
                        Image(systemName: "figure.walk")
                        Text("+\(Int(stepBonus)) earned from steps")
                            .contentTransition(.numericText())
                    }
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Theme.info)
                    .padding(.top, 2)
                    .accessibilityLabel("Plus \(Int(stepBonus)) calories earned from steps")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .cardElevated(padding: Theme.Space.lg)
    }

    private func heroRow(_ label: String, _ value: Int, _ color: Color) -> some View {
        heroRow(label, "\(value)", color, monospaced: true)
    }

    /// String-value variant — used for the celebratory "Reached 🎉  ✓" row where a
    /// numeric remainder would be misleading.
    private func heroRow(_ label: String, _ valueText: String, _ color: Color,
                         monospaced: Bool = false) -> some View {
        HStack {
            Text(label).foregroundStyle(Theme.textSecondary)
            Spacer()
            Text(valueText)
                .font(.headline.weight(.bold))
                .monospacedDigit()
                .contentTransition(.numericText())
                .foregroundStyle(color)
        }
        .font(.subheadline)
        .accessibilityElement(children: .combine)
    }

    // MARK: Activity row (steps + water)
    private var activityRow: some View {
        HStack(spacing: Theme.Space.md) {
            stepsCard
            waterCard
        }
    }

    private var stepGoal: Int { max(profile.dailyStepGoal, 0) }
    private var stepProgress: Double { stepGoal > 0 ? Double(todaySteps) / Double(stepGoal) : 0 }

    private var stepsCard: some View {
        VStack(alignment: .leading, spacing: Theme.Space.sm) {
            Label("Steps", systemImage: "figure.walk")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.info)
            HStack(spacing: 12) {
                ZStack {
                    ProgressRing(progress: stepProgress, lineWidth: 8, color: Theme.info,
                                 track: Color.white.opacity(0.07))
                        .frame(width: 54, height: 54)
                    Image(systemName: "shoeprints.fill")
                        .font(.caption).foregroundStyle(Theme.info)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(todaySteps, format: .number)
                        .font(.title3.weight(.bold)).monospacedDigit()
                        .contentTransition(.numericText())
                        .minimumScaleFactor(0.7).lineLimit(1)
                    Text("of \(stepGoal.formatted())")
                        .font(.caption2).foregroundStyle(Theme.textSecondary)
                        .monospacedDigit().lineLimit(1)
                }
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardElevated()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Steps \(todaySteps) of \(stepGoal)")
    }

    private var waterGoal: Double { profile.waterTargetOz }
    private var waterProgress: Double { waterGoal > 0 ? waterToday / waterGoal : 0 }
    /// One drink = her chosen container size (bottle/glass), so she never thinks in oz.
    private var containerOz: Double { profile.waterContainerOz > 0 ? profile.waterContainerOz : 16.9 }
    private var containersDoneToday: Int { Int((waterToday / containerOz).rounded()) }
    private var containerGoal: Int { profile.waterGoalContainers }

    @State private var showWaterSheet = false

    private var waterCard: some View {
        VStack(alignment: .leading, spacing: Theme.Space.sm) {
            HStack {
                Label("Water", systemImage: "drop.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.water)
                    .lineLimit(1)
                Spacer(minLength: 0)
                Button {
                    // Log one container (her bottle/glass), not a fixed 8 oz.
                    context.insert(WaterEntry(amountOz: containerOz))
                    try? context.save()
                    waterPulse += 1
                } label: {
                    Image(systemName: "plus")
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(Theme.water)
                        .frame(width: 30, height: 30)
                        .background(Theme.water.opacity(0.15), in: Circle())
                        .overlay(Circle().strokeBorder(Theme.water.opacity(0.30), lineWidth: 1))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Add one \(profile.waterContainerLabel) of water")
            }
            HStack(spacing: 12) {
                ZStack {
                    ProgressRing(progress: waterProgress, lineWidth: 8, color: Theme.water,
                                 track: Color.white.opacity(0.07))
                        .frame(width: 50, height: 50)
                    Image(systemName: "drop.fill")
                        .font(.caption).foregroundStyle(Theme.water)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text("\(containersDoneToday) / \(containerGoal)")
                        .font(.title3.weight(.bold)).monospacedDigit()
                        .contentTransition(.numericText())
                        .minimumScaleFactor(0.7).lineLimit(1)
                    Text("\(profile.waterContainerLabel)s · \(Int(waterToday)) oz")
                        .font(.caption2).foregroundStyle(Theme.textSecondary)
                        .monospacedDigit().lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            // Tap the ring/numbers to log a custom amount or change your bottle size.
            .contentShape(Rectangle())
            .onTapGesture { showWaterSheet = true }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardElevated()
        .sheet(isPresented: $showWaterSheet) { WaterLogSheet(profile: profile) }
    }

    // MARK: Macros
    private var macrosCard: some View {
        VStack(alignment: .leading, spacing: Theme.Space.md) {
            HStack {
                Text("Macros").font(.subheadline.weight(.semibold))
                Spacer()
                Text("\(Int(consumed.rounded())) kcal")
                    .font(.caption.weight(.medium)).monospacedDigit()
                    .contentTransition(.numericText())
                    .foregroundStyle(Theme.textSecondary)
            }
            MacroBar(label: "Protein", value: protein, target: macros.proteinG, color: Theme.protein)
            MacroBar(label: "Carbs", value: carbs, target: macros.carbsG, color: Theme.carbs)
            MacroBar(label: "Fat", value: fat, target: macros.fatG, color: Theme.fat)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardElevated()
    }

    // MARK: Streak + coach
    /// "Logging streak" = days she actively logged (food, water, or a manual weigh-in). Auto-
    /// imported Health data — steps, and scale-synced weights — does NOT count, or backfilling
    /// ~30 days of Health steps would read as a 30-day streak she never earned. See StreakCalculator.
    private var streak: Int {
        StreakCalculator.loggingStreak(foods: allFood, waters: water, weights: weights)
    }

}
