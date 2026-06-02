import Foundation

/// Builds the system prompt (persona) and a compact, data-grounded context summary
/// that gets injected into every coach turn. Keeping this pure and static makes it
/// trivial to test and to reuse from the view's `Task`.
///
/// Design notes:
/// - We deliberately emphasize the *trend* (smoothed via `TrendCalculator`) over any
///   single daily scale reading, mirroring the rest of the app's philosophy.
/// - We pre-compute the human-friendly assessment wording here so the model is steered
///   toward an encouraging, sustainable framing rather than re-deriving it (and possibly
///   moralizing about the rate).
/// - Numbers are rounded to whole units; the model never needs more precision than the UI.
enum CoachContext {

    // MARK: - Public entry points

    /// The complete system string: persona + a freshly-built data snapshot, plus (optionally)
    /// the coach's long-term memory so she carries continuity across sessions.
    /// This is what `CoachView` passes to `AnthropicClient.chat(system:)`.
    ///
    /// - Parameter memory: the durable `CoachMemory` (notes + rolling summary). Optional and
    ///   defaulting to `nil` so all existing call sites and tests keep their exact behavior;
    ///   when present (and non-empty) its blocks are injected AFTER the live numbers, clearly
    ///   labeled as qualitative context with an explicit note that the live numbers win. The
    ///   memory is qualitative only — it never carries weights/calories/targets (those stay in
    ///   the data snapshot above), so it can't override the authoritative numbers.
    static func system(profile: UserProfile,
                       foods: [FoodEntry],
                       weights: [WeightEntry],
                       memory: CoachMemory? = nil) -> String {
        persona(profile: profile)
            + bioLine(profile: profile)
            + "\n\nHere is her current data:\n"
            + summary(profile: profile, foods: foods, weights: weights)
            + "\n\nUse this data to make your replies specific and personal, but speak naturally — "
            + "don't dump numbers or read the data back like a report unless she asks. "
            + "Today's date is \(Self.longDate.string(from: .now))."
            + memoryBlock(memory)
            + "\n\n" + toolGuidance(profile: profile)
    }

    /// The long-term-memory section of the system prompt: the durable qualitative notes and
    /// the rolling conversation summary, each injected only when non-empty.
    ///
    /// Placed AFTER the live-numbers snapshot on purpose, and prefixed with an explicit
    /// precedence rule: the computed numbers above are authoritative, and these notes are
    /// qualitative background only. The memory never contains numbers (the consolidation step
    /// forbids it), but stating the precedence keeps the model from ever treating a remembered
    /// aside as a current stat. Returns "" when there's nothing to add, so the prompt is byte-
    /// for-byte identical to the pre-memory behavior whenever `memory` is nil/empty.
    static func memoryBlock(_ memory: CoachMemory?) -> String {
        guard let memory else { return "" }
        let notes = memory.profileNotes.trimmingCharacters(in: .whitespacesAndNewlines)
        let summary = memory.conversationSummary.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !notes.isEmpty || !summary.isEmpty else { return "" }

        var out = "\n\nThe numbers above are computed live from her real data and are the "
            + "single source of truth — always defer to them. The notes below are qualitative "
            + "long-term context to help you sound like you actually know her and remember your "
            + "past conversations; they contain no current stats and never override the numbers."
        if !notes.isEmpty {
            out += "\n\nWhat you remember about her (durable notes):\n\(notes)"
        }
        if !summary.isEmpty {
            out += "\n\nWhere things stand from earlier conversations (summary):\n\(summary)"
        }
        return out
    }

    /// Behavioral rules for the small set of settings-changing tools (see `CoachTools`).
    /// Two jobs: tell the model these tools exist and when to reach for them, and draw a
    /// firm health-safety line — there is no tool for weight/calorie targets, and the
    /// model must gently refuse anything that amounts to under-eating.
    static func toolGuidance(profile: UserProfile) -> String {
        let role: String
        switch profile.pace.direction {
        case .lose:     role = "She is working toward gentle, sustainable weight loss."
        case .gain:     role = "She is working toward a healthy lean gain."
        case .maintain: role = "She is maintaining a healthy weight."
        }
        return """
        You can adjust a few of her encouragement settings with tools: her daily step \
        goal (set_step_goal), her daily water goal in containers (set_water_goal_containers), \
        and her goal pace (set_pace). When she clearly asks to change one of these \
        ("bump my step goal to 12k", "I want to drink more water", "put me on a steadier \
        pace"), call the matching tool with the value she asked for. You do NOT need to \
        ask permission first — the app will show her a one-tap confirmation before \
        anything actually changes, so just call the tool. After a change is applied, \
        reply warmly and briefly (e.g. "Done — 12k it is 💪"). If she declines, respond \
        graciously with zero pressure. If she's vague about the number, ask a quick \
        clarifying question instead of guessing.

        Coaching style. \(role) You have NO tool for weight/calorie/macro targets, so don't \
        claim you can change those — only step, water, and pace. If she's tempted by an \
        extreme shortcut (barely eating, crash dieting, skipping meals to lose faster), NEVER \
        refuse, lecture, or shut her down. Instead be the knowledgeable friend who levels with \
        her: explain plainly why that tends to backfire (tanks energy, burns muscle, slows \
        metabolism, usually rebounds), then TEACH her the ways that actually work and still \
        get her there — a sensible deficit, protein, strength training, steps, sleep, \
        consistency. Inform and empower; show her a better path, never block her. A faster \
        pace is fine to affirm while noting steady tends to last longer.
        """
    }

    /// Her own editable "about me" bio (Settings → About you), so Vita actually KNOWS her —
    /// the app understands her, it's not just a database. Empty → nothing added.
    static func bioLine(profile: UserProfile) -> String {
        let bio = profile.onboardingNote.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !bio.isEmpty else { return "" }
        let name = profile.name.isEmpty ? "She" : profile.name
        return "\n\nA bit about \(name), in her own words — keep this in mind and reference it "
            + "naturally when it's relevant: \"\(bio)\""
    }

    /// The persona / behavioral contract for the coach. Pure function of the profile.
    static func persona(profile: UserProfile) -> String {
        let coach = profile.coachName.isEmpty ? "Vita" : profile.coachName
        let user = profile.name.isEmpty ? "your friend" : profile.name
        let role: String
        switch profile.pace.direction {
        case .lose:     role = "weight-loss buddy"
        case .gain:     role = "muscle-building buddy"
        case .maintain: role = "healthy-habits buddy"
        }
        return """
        You are \(coach), \(user)'s warm, encouraging, knowledgeable friend and \(role). \
        Never clinical, never a drill sergeant, never shaming. Use their name. \
        Emphasize the TREND, not the daily scale number. \
        Celebrate consistency, effort, and real progress — her trend is moving, show her! \
        Be genuinely informative and helpful: if she's curious about an extreme shortcut, \
        don't refuse or moralize — explain the downsides plainly and TEACH her the healthier \
        ways she can still reach her goal. Empower her with knowledge; never gatekeep. \
        For genuinely medical questions, suggest a doctor or registered dietitian. \
        Keep replies concise, warm, specific to their data, and a little fun.
        """
    }

    /// A compact, human-readable snapshot of the user's current numbers and momentum.
    /// Safe to call with empty `foods`/`weights` — it degrades gracefully.
    static func summary(profile: UserProfile,
                        foods: [FoodEntry],
                        weights: [WeightEntry]) -> String {
        var lines: [String] = []

        let unit = profile.unitSystem.weightUnit
        let name = profile.name.isEmpty ? "She" : profile.name

        // Weight used as the basis for targets: smoothed trend, else start weight.
        let basisWeight = TrendCalculator.currentTrend(weights)
            ?? (profile.startWeightLbs > 0 ? profile.startWeightLbs : 150)

        lines.append("Name: \(name)")

        // Goal + pace
        if profile.goalWeightLbs > 0 {
            lines.append("Goal weight: \(lbs(profile.goalWeightLbs)) \(unit) "
                         + "(pace: \(profile.pace.label.lowercased()), ~\(rate(profile.pace.weeklyRateLbs)) \(unit)/week)")
        } else {
            lines.append("Goal: \(profile.pace.label.lowercased()) "
                         + "(~\(rate(profile.pace.weeklyRateLbs)) \(unit)/week)")
        }

        // Daily calorie + macro targets (computed from the profile + basis weight).
        let goal = profile.calorieGoal(weightLbs: basisWeight)
        let macros = profile.macroTargets(weightLbs: basisWeight)
        var targetLine = "Daily targets: \(Int(goal.dailyCalories.rounded())) kcal, "
            + "\(Int(macros.proteinG)) g protein, \(Int(macros.carbsG)) g carbs, \(Int(macros.fatG)) g fat"
        if goal.wasClampedToFloor {
            targetLine += " (calories held at a safe minimum — don't suggest eating less)"
        }
        lines.append(targetLine)

        // Today's intake so far.
        let today = todaysFoods(foods)
        if today.isEmpty {
            lines.append("Today's intake: nothing logged yet")
        } else {
            let cals = today.reduce(0) { $0 + $1.calories }
            let protein = today.reduce(0) { $0 + $1.proteinG }
            let remaining = goal.dailyCalories - cals
            var intake = "Today's intake so far: \(Int(cals.rounded())) kcal, "
                + "\(Int(protein.rounded())) g protein across \(today.count) item\(today.count == 1 ? "" : "s")"
            if remaining > 0 {
                intake += " (\(Int(remaining.rounded())) kcal left for the day)"
            } else {
                intake += " (at or over the calorie target — that's okay, one day doesn't define the week)"
            }
            lines.append(intake)
        }

        // Weight trend + weekly rate + assessment wording.
        if let trend = TrendCalculator.currentTrend(weights) {
            let weeklyRate = TrendCalculator.ratePerWeek(weights)
            lines.append("Current weight trend: \(lbs(trend)) \(unit) "
                         + "(this is the smoothed trend, not today's raw scale number)")
            lines.append("Recent rate: \(signedRate(weeklyRate)) \(unit)/week — \(assessmentPhrase(weeklyRate, weight: trend, direction: profile.pace.direction))")

            if profile.goalWeightLbs > 0,
               let eta = TrendCalculator.projectedGoalDate(weights, goalLbs: profile.goalWeightLbs) {
                lines.append("At this pace they'd reach their goal around \(Self.monthYear.string(from: eta))")
            }
        } else {
            lines.append("Weight trend: no weigh-ins logged yet (encourage a first weigh-in, gently)")
        }

        // Logging streak — consecutive days back from today with any food or weight entry.
        let streak = loggingStreak(foods: foods, weights: weights)
        switch streak {
        case 0:
            lines.append("Logging streak: nothing logged today yet")
        case 1:
            lines.append("Logging streak: 1 day (logged today)")
        default:
            lines.append("Logging streak: \(streak) days in a row — celebrate this consistency")
        }

        return lines.map { "- " + $0 }.joined(separator: "\n")
    }

    // MARK: - Streak

    /// Number of consecutive calendar days, counting back from today, that have at
    /// least one `FoodEntry` or `WeightEntry`. Returns 0 if today has nothing yet.
    static func loggingStreak(foods: [FoodEntry],
                              weights: [WeightEntry],
                              calendar: Calendar = .current,
                              now: Date = .now) -> Int {
        // Collect the set of start-of-day timestamps that have any activity.
        var loggedDays = Set<Date>()
        for f in foods { loggedDays.insert(calendar.startOfDay(for: f.date)) }
        for w in weights { loggedDays.insert(calendar.startOfDay(for: w.date)) }
        guard !loggedDays.isEmpty else { return 0 }

        var streak = 0
        var day = calendar.startOfDay(for: now)
        while loggedDays.contains(day) {
            streak += 1
            guard let prev = calendar.date(byAdding: .day, value: -1, to: day) else { break }
            day = prev
        }
        return streak
    }

    // MARK: - Helpers

    /// Food entries whose `date` falls on today.
    static func todaysFoods(_ foods: [FoodEntry],
                            calendar: Calendar = .current,
                            now: Date = .now) -> [FoodEntry] {
        foods.filter { calendar.isDate($0.date, inSameDayAs: now) }
    }

    /// Friendly, encouraging phrasing for the current rate, derived from
    /// `TrendCalculator.assess`. We pre-translate the enum so the model gets the *tone*
    /// we want rather than inventing its own (possibly harsher) framing.
    private static func assessmentPhrase(_ weeklyRate: Double, weight: Double,
                                         direction: GoalPace.Direction) -> String {
        switch direction {
        case .lose:
            switch TrendCalculator.assess(ratePerWeek: weeklyRate, currentWeightLbs: weight) {
            case .gainingOrFlat:
                return "holding roughly steady right now (a normal plateau — reassure, don't alarm)"
            case .slow:
                return "a gentle, gradual loss (sustainable and totally fine)"
            case .ideal:
                return "right in the healthy, sustainable sweet spot"
            case .fast:
                return "a brisk pace — affirm it but gently remind them that slow and steady protects muscle and lasts"
            }
        case .gain:
            if weeklyRate >= 0.75 { return "gaining briskly — affirm it, and note a slightly slower gain stays leaner" }
            if weeklyRate >= 0.15 { return "a steady lean gain (right where we want it)" }
            if weeklyRate > -0.15 { return "holding roughly steady — a touch more fuel will tip it into a gain (reassure, don't alarm)" }
            return "drifting down a little — gently nudge toward eating a bit more to keep building"
        case .maintain:
            if abs(weeklyRate) < 0.25 { return "holding steady — exactly the goal" }
            return weeklyRate < 0 ? "drifting down slightly from maintenance" : "drifting up slightly from maintenance"
        }
    }

    private static func lbs(_ v: Double) -> String { String(Int(v.rounded())) }
    private static func rate(_ v: Double) -> String {
        v == v.rounded() ? String(Int(v)) : String(format: "%.1f", v)
    }
    /// Signed weekly rate, e.g. "down 0.8" / "up 0.3" / "steady".
    private static func signedRate(_ v: Double) -> String {
        let mag = abs(v)
        if mag < 0.05 { return "holding steady" }
        let dir = v < 0 ? "down" : "up"
        return "\(dir) \(String(format: "%.1f", mag))"
    }

    private static let longDate: DateFormatter = {
        let f = DateFormatter(); f.dateStyle = .full; f.timeStyle = .none; return f
    }()
    private static let monthYear: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "MMMM yyyy"; return f
    }()
}
