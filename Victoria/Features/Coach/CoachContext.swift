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
    ///
    /// - Parameter workouts: her logged (legacy dashboard) `WorkoutEntry` rows. Optional and
    ///   defaulting to `[]` so every existing call site and test keeps its exact behavior; when
    ///   non-empty, a compact "recent workouts" block is folded into the snapshot.
    /// - Parameter sessions/exercises: her rich Workouts-tab data — `WorkoutSession`s and their
    ///   `ExerciseEntry`s (linked by `sessionID`). Both default to `[]` for the same reason; when
    ///   present, a "recent gym sessions" block (with the machines she trained) is added so Vita
    ///   can see exactly what she lifted, not just that she worked out.
    /// - Parameter water: today's `WaterEntry` rows. Optional and defaulting to `[]` for the same
    ///   reason; when present, today's hydration is summed against her goal in the snapshot.
    static func system(profile: UserProfile,
                       foods: [FoodEntry],
                       weights: [WeightEntry],
                       workouts: [WorkoutEntry] = [],
                       water: [WaterEntry] = [],
                       steps: [StepsEntry] = [],
                       sessions: [WorkoutSession] = [],
                       exercises: [ExerciseEntry] = [],
                       sleep: [SleepEntry] = [],
                       detected: [DetectedWorkout] = [],
                       vitals: [VitalsEntry] = [],
                       memory: CoachMemory? = nil,
                       plan: CoachPlan? = nil) -> String {
        let parts = systemParts(profile: profile, foods: foods, weights: weights,
                                workouts: workouts, water: water, steps: steps,
                                sessions: sessions, exercises: exercises,
                                sleep: sleep, detected: detected, vitals: vitals,
                                memory: memory, plan: plan)
        return parts.stable + parts.volatile
    }

    /// The system prompt split at its CACHE BOUNDARY, for Anthropic prompt caching.
    ///
    /// `stable` holds everything that is byte-identical across every turn of a session —
    /// persona, her bio, tool rules, formatting rules. It goes FIRST in the prompt and gets a
    /// `cache_control` breakpoint, so together with the (deterministic) tool schemas it's read
    /// from cache at ~10% price on every turn after the first. `volatile` holds the live data
    /// snapshot (today's foods, trend, memory, plan, today's date) — it changes constantly and
    /// therefore comes AFTER the breakpoint, paying full price only for itself.
    ///
    /// One invariant to protect: nothing time- or data-dependent may leak into `stable`
    /// (a date, a count, a weight) — a single changed byte there invalidates the whole cache.
    static func systemParts(profile: UserProfile,
                            foods: [FoodEntry],
                            weights: [WeightEntry],
                            workouts: [WorkoutEntry] = [],
                            water: [WaterEntry] = [],
                            steps: [StepsEntry] = [],
                            sessions: [WorkoutSession] = [],
                            exercises: [ExerciseEntry] = [],
                            sleep: [SleepEntry] = [],
                            detected: [DetectedWorkout] = [],
                            vitals: [VitalsEntry] = [],
                            memory: CoachMemory? = nil,
                            plan: CoachPlan? = nil) -> (stable: String, volatile: String) {
        // STABLE — persona + bio + behavioral rules. Changes only when the profile itself
        // changes (name, pace, bio edit), which correctly re-writes the cache once.
        let stable = persona(profile: profile) + bioLine(profile: profile)
            + "\n\n" + toolGuidance(profile: profile)
            + "\n\n" + formattingGuidance

        // VOLATILE — the live snapshot + usage guidance (carries today's date) + memory + plan.
        let data = "\n\nHere is her current data:\n"
            + summary(profile: profile, foods: foods, weights: weights, workouts: workouts,
                      water: water, steps: steps, sessions: sessions, exercises: exercises,
                      sleep: sleep, detected: detected, vitals: vitals)
        let usage = "\n\nUse this data — including the exact foods she logged today and this week, "
            + "their per-item breakdown/notes, her water, and her recent workouts — to make "
            + "your replies specific and personal, but speak naturally — "
            + "don't dump numbers or read the data back like a report unless she asks. "
            + "You CAN see her individual logged foods above (including each meal's component "
            + "breakdown and the assumptions in its notes), her water, and her workouts, so never "
            + "say you can't see them; reference them by name when it's relevant. "
            + "When she sends a PHOTO, actually look at it and respond to what's in it. If it's "
            + "food she wants logged, estimate its calories + macros from the image and call the "
            + "log_food tool (one call per distinct item) — you don't need to ask her for the numbers. "
            + "Today's date is \(Self.longDate.string(from: .now))."
        let volatile = data + usage + memoryBlock(memory) + planBlock(plan)
        return (stable, volatile)
    }

    /// Injects the user's adaptive Plan (see docs/adaptive-plan.md) so Vita is "the plan talking
    /// back" — she can reference it, explain it, and (later) adjust it. Compact summary only; the
    /// full plan lives on Progress. Empty string when there's no plan yet (prompt unchanged).
    static func planBlock(_ plan: CoachPlan?) -> String {
        guard let plan, !plan.headline.isEmpty || plan.hasRange || !plan.insights.isEmpty else { return "" }
        var out = "\n\nHer current Plan (the adaptive plan she built with you — reference it and explain it "
            + "naturally; she can ask you to adjust it):"
        if !plan.headline.isEmpty { out += "\n- \(plan.headline)" }
        if plan.hasRange { out += "\n- Daily fuel range: \(plan.calorieRangeText) kcal (a floor to meet + a soft ceiling — hitting the range is the win, going under the floor is not)" }
        if plan.proteinTarget > 0 { out += "\n- Protein target: \(Int(plan.proteinTarget)) g" }
        let assessment = plan.assessment.trimmingCharacters(in: .whitespacesAndNewlines)
        if !assessment.isEmpty { out += "\n- Current read: \(assessment)" }
        if !plan.insights.isEmpty {
            out += "\n- The focus right now:"
            for i in plan.insights.prefix(5) { out += "\n  • \(i.title) — \(i.body)" }
        }
        return out
    }

    /// How Vita should format her replies. Her messages render as markdown in a phone-sized chat
    /// bubble (via `MarkdownMessage`), so this steers her toward short, scannable, human text and
    /// AWAY from heavy document structure (big headings, horizontal rules) that reads cold in a
    /// chat — the same "use markdown deliberately, keep it light" guidance the big assistants get.
    /// The client renderer handles whatever she emits; this just keeps the habits clean so a reply
    /// never looks like a spec sheet.
    static let formattingGuidance = """
    Formatting your replies: your messages render as markdown in a small chat bubble, so write \
    for a phone screen:
    - Keep it short — usually a sentence or two. This is a chat, not an essay or a report.
    - Use a short bulleted list (lines starting with "- ") only when you're genuinely listing \
    two or more things; otherwise just write a normal sentence.
    - Use **bold** sparingly — at most one key number or word.
    - Do NOT use headings (#) or horizontal rules (---) — they look heavy and clinical in a chat. \
    No tables or code blocks.
    - Plain warmth over structure. A little emoji is welcome in moderation.
    """

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

        You ALSO have tools to log and edit her data on request — log_food, edit_food, \
        delete_food, log_water, log_weight, log_workout (log a training session — its kind plus, \
        for a gym day, the muscle groups and the actual machines/moves she did with weight·reps·sets; \
        use it whenever she mentions training), set_weight_goal — and to SAVE durable facts about \
        her with remember_about_user (e.g. she takes creatine, sees a nutritionist, is \
        vegetarian, her gym days are Mon/Wed/Fri) — and to forget_about_user when she says a \
        remembered fact is wrong or no longer true (to CORRECT one: forget the old, remember the new). \
        When she shares something lasting about herself, OR asks you to "remember"/"update my \
        profile/note" something, call remember_about_user so it persists across every future \
        conversation. For her adaptive Plan you can record a change with update_plan, OR actually \
        EDIT it — its targets, focus, range, or read — with edit_plan when she asks to adjust it; but \
        before any extreme change (like a very low calorie range) educate her first, don't just enable \
        it. CRITICAL HONESTY \
        RULE: only tell her you've done / saved / logged / updated / remembered something AFTER \
        you've actually called the matching tool and it succeeded — NEVER say "done" or "I saved \
        that" for something you didn't actually do. If you genuinely lack a tool for what she \
        asks, say so plainly instead of pretending.

        Coaching style. \(role) You have NO tool for CALORIE or MACRO targets (those stay \
        computed and safely floored), so don't claim you can change those. If she's tempted by an \
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
    /// Safe to call with empty `foods`/`weights`/`workouts`/`water`/`sessions` — it degrades
    /// gracefully. All of `workouts`/`water`/`steps`/`sessions`/`exercises` default to empty so
    /// existing callers (and tests) are byte-for-byte unchanged; pass them to give Vita the full
    /// picture (so she never says "I can't see X").
    static func summary(profile: UserProfile,
                        foods: [FoodEntry],
                        weights: [WeightEntry],
                        workouts: [WorkoutEntry] = [],
                        water: [WaterEntry] = [],
                        steps: [StepsEntry] = [],
                        sessions: [WorkoutSession] = [],
                        exercises: [ExerciseEntry] = [],
                        sleep: [SleepEntry] = [],
                        detected: [DetectedWorkout] = [],
                        vitals: [VitalsEntry] = []) -> String {
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
        if profile.startWeightLbs > 0 {
            lines.append("Starting weight (when she began): \(lbs(profile.startWeightLbs)) \(unit) "
                         + "— the progress chart measures from here; she can correct it in Settings "
                         + "or ask you to (set_start_weight)")
        }

        // Daily calorie + macro targets — the SAME numbers the rings show. Read the OVERRIDE-AWARE
        // `dailyCalorieTarget` (not the raw computed `calorieGoal`) so that when a Plan is active its
        // calorie target reaches Vita too — otherwise she'd quote a different number than Nutrients/Today.
        let calTarget = profile.dailyCalorieTarget(weightLbs: basisWeight)
        let macros = profile.macroTargets(weightLbs: basisWeight)
        let calRange = profile.calorieGoalRange(weightLbs: basisWeight)
        let calGoalText = profile.calorieGoalText(weightLbs: basisWeight)
        let calLead = (calRange.high.isFinite && calRange.high > calRange.low)
            ? "Daily calorie RANGE: \(calGoalText) kcal (a floor to reach + a soft ceiling — being IN the range is the win, not one exact number)"
            : "Daily calorie target: \(calGoalText) kcal"
        var targetLine = calLead
            + ", \(Int(macros.proteinG)) g protein, \(Int(macros.carbsG)) g carbs, \(Int(macros.fatG)) g fat"
        if profile.calorieGoal(weightLbs: basisWeight).wasClampedToFloor {
            targetLine += " (calories held at a safe minimum — don't suggest eating less)"
        }
        lines.append(targetLine)

        // Today's intake so far — totals PLUS the exact items, so Vita can see precisely what
        // she ate. This is the fix for "I can't see the specific food items you've logged":
        // without the item list the model only ever had the count.
        let today = todaysFoods(foods)
        if today.isEmpty {
            lines.append("Today's intake: nothing logged yet")
        } else {
            let cals = today.reduce(0) { $0 + $1.totalCalories }
            let protein = today.reduce(0) { $0 + $1.totalProteinG }
            let carbs = today.reduce(0) { $0 + $1.totalCarbsG }
            let fat = today.reduce(0) { $0 + $1.totalFatG }
            var intake = "Today's intake so far: \(Int(cals.rounded())) kcal, "
                + "\(Int(protein.rounded())) g protein, \(Int(carbs.rounded())) g carbs, "
                + "\(Int(fat.rounded())) g fat across \(today.count) item\(today.count == 1 ? "" : "s")"
            switch profile.calorieStatus(consumed: cals, weightLbs: basisWeight) {
            case .under:
                intake += " (\(Int((calRange.low - cals).rounded())) kcal under her range floor — she has room to eat more; encourage it, never restriction)"
            case .inRange:
                intake += " (right in her calorie range — that's the win)"
            case .over:
                intake += " (a bit over her range's soft ceiling — that's okay, one day doesn't define the week; never shame)"
            }
            lines.append(intake)

            // The actual items — newest first, each with its macros. THIS is what lets Vita
            // name specific foods ("that In-N-Out") instead of admitting it can't see them.
            lines.append("The exact foods she logged today (newest first):")
            lines.append(contentsOf: itemLines(today))
        }

        // Today's water vs her goal — so "have I had enough water?" is answerable, and Vita can
        // see hydration the same way the dashboard does. Goal is her override or the computed
        // ~½-bodyweight default; expressed in oz AND her own containers so it reads naturally.
        let waterOz = todaysWaterOz(water)
        let goalOz = profile.waterTargetOz
        let container = profile.waterContainerLabel.isEmpty ? "container" : profile.waterContainerLabel
        var waterLine = "Today's water: \(Int(waterOz.rounded())) of \(Int(goalOz.rounded())) oz goal "
            + "(~\(profile.waterGoalContainers) \(container)\(profile.waterGoalContainers == 1 ? "" : "s"))"
        if waterOz <= 0 { waterLine += " — none logged yet today" }
        else if waterOz >= goalOz { waterLine += " — goal met, nice" }
        lines.append(waterLine)

        // Today's steps vs her goal — so "how many steps today?" / "did I move enough?" is
        // answerable, and Vita can factor real activity into advice (not just the goal number).
        let stepGoal = max(profile.dailyStepGoal, 0)
        if let todaySteps = steps.first(where: { Calendar.current.isDateInToday($0.date) })?.count {
            var stepLine = "Today's steps: \(todaySteps.formatted())"
            if stepGoal > 0 { stepLine += " of \(stepGoal.formatted()) goal" + (todaySteps >= stepGoal ? " — goal met" : "") }
            lines.append(stepLine)
        }

        // This week at a glance — per-day food totals for the last 7 days that have logs, so
        // "how's my week?" is answerable from real food numbers (not just the weight trend).
        let weekLines = weeklyTotalLines(foods)
        if !weekLines.isEmpty {
            lines.append("This week's daily food totals (most recent first):")
            lines.append(contentsOf: weekLines)
        }

        // Recent workouts — so Vita can see she's actually training (and reward showing up),
        // never claiming she can't see the gym. Compact: last few sessions, newest first.
        let recentWorkouts = workoutLines(workouts)
        if !recentWorkouts.isEmpty {
            lines.append("Recent workouts (most recent first):")
            lines.append(contentsOf: recentWorkouts)
        }

        // Recent Workouts-tab sessions — the richer model behind the Workouts tab, with the actual
        // machines she trained (weight × sets). This is what lets Vita say "nice work on that 90lb
        // chest press" instead of just "you worked out". Kept alongside the legacy block above.
        let recentSessions = sessionLines(sessions, exercises: exercises)
        if !recentSessions.isEmpty {
            lines.append("Recent gym/training sessions (most recent first):")
            lines.append(contentsOf: recentSessions)
        }

        // Tracker data mirrored from Apple Health (Fitbit etc.) — passive, so it's context
        // ("she moved / slept X") and never a logging achievement to praise as showing up.
        let sleepLine = lastNightSleepLine(sleep)
        if let sleepLine { lines.append(sleepLine) }
        if let vitalsLine = recoveryVitalsLine(vitals) { lines.append(vitalsLine) }
        if let signal = RecoverySignal.fromDailyVitals(vitals) { lines.append(signal.coachLine) }
        let detectedLines = detectedWorkoutLines(detected)
        if !detectedLines.isEmpty {
            lines.append("Workouts her fitness tracker auto-detected (most recent first — these were "
                + "picked up automatically, she didn't log them by hand):")
            lines.append(contentsOf: detectedLines)
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

        // Coming back after a break — WITHOUT this, a returning user looks like a brand-new
        // one (streak 1, sparse week, light intake) and the coach draws exactly the wrong
        // conclusions ("you're under-eating", "your numbers dropped"). The gap means she
        // wasn't LOGGING — life happened — not that she wasn't eating.
        if let away = StreakCalculator.daysSinceLastLog(foods: foods, waters: water,
                                                        weights: weights), away >= 4 {
            lines.append("IMPORTANT: she's just coming back after \(away) days away from the app "
                + "(no logs in that window). The empty days mean she wasn't logging — NOT that she "
                + "wasn't eating, and NOT a decline in her progress. Never treat the gap as "
                + "under-eating, a relapse, or a broken streak to feel bad about. Welcome her back "
                + "warmly, treat today as a clean fresh start, and if today's intake looks light "
                + "remember she may still be catching up on logging — ask, don't assume.")
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
        // Delegates to the shared StreakCalculator so the coach reports the SAME streak as the
        // dashboard and widget: active logging only (food + manual weigh-ins). Auto-imported steps
        // and scale-synced weights don't count. (Water isn't in the coach's data here, so water-
        // only days aren't counted — a rare edge that doesn't move the headline number.)
        StreakCalculator.loggingStreak(foods: foods, weights: weights, calendar: calendar, now: now)
    }

    // MARK: - Helpers

    /// Food entries whose `date` falls on today.
    static func todaysFoods(_ foods: [FoodEntry],
                            calendar: Calendar = .current,
                            now: Date = .now) -> [FoodEntry] {
        foods.filter { calendar.isDate($0.date, inSameDayAs: now) }
    }

    /// Total fluid ounces of water logged today (sum of today's `WaterEntry` amounts).
    static func todaysWaterOz(_ water: [WaterEntry],
                              calendar: Calendar = .current,
                              now: Date = .now) -> Double {
        water.filter { calendar.isDate($0.date, inSameDayAs: now) }
             .reduce(0) { $0 + $1.amountOz }
    }

    /// One compact line per recent workout: "Today — Push day (Strength), 45 min, 320 kcal".
    /// Newest first, capped at `limit`; date is named (Today/Yesterday) or weekday+date. The
    /// optional focus, duration, calories, and free-text notes are appended only when present,
    /// so a bare "showed up" log still reads cleanly. Empty when there are no workouts.
    static func workoutLines(_ workouts: [WorkoutEntry],
                             limit: Int = 6,
                             now: Date = .now,
                             calendar: Calendar = .current) -> [String] {
        let sorted = workouts.sorted { $0.date > $1.date }
        let startToday = calendar.startOfDay(for: now)
        let yesterday = calendar.date(byAdding: .day, value: -1, to: startToday)
        var out = sorted.prefix(limit).map { w -> String in
            let day = calendar.startOfDay(for: w.date)
            let when: String
            if calendar.isDate(day, inSameDayAs: startToday) { when = "Today" }
            else if let y = yesterday, calendar.isDate(day, inSameDayAs: y) { when = "Yesterday" }
            else { when = Self.weekdayDate.string(from: day) }

            let rawTitle = w.title.trimmingCharacters(in: .whitespacesAndNewlines)
            let title = rawTitle.isEmpty ? w.type.label : rawTitle
            var line = "\(when) — \(title) (\(w.type.label))"
            if let focus = w.focus { line += ", \(focus.label.lowercased())" }
            if w.durationMinutes > 0 { line += ", \(w.durationMinutes) min" }
            if let kcal = w.caloriesBurned, kcal > 0 { line += ", \(Int(kcal.rounded())) kcal" }
            let notes = (w.notes ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !notes.isEmpty { line += " — \(trimmedNote(notes, max: 200))" }
            return line
        }
        if sorted.count > limit {
            let extra = sorted.count - limit
            out.append("…and \(extra) more workout\(extra == 1 ? "" : "s")")
        }
        return out
    }

    /// One compact line per recent **Workouts-tab** session (the rich `WorkoutSession` model), newest
    /// first, capped at `limit`. Each reads like:
    ///   "Today — Gym (Chest, Arms), 50 min, 3 exercises: Chest press 90lb 3x10, Incline press 50lb 3x10, …"
    /// The session's kind/focuses/duration come from `WorkoutSession`; the per-machine detail is its
    /// `ExerciseEntry` rows (filtered by `sessionID`, kept in catalog order so it reads intentionally,
    /// then capped so a marathon day can't blow up the prompt). Cardio sessions have no exercises, so
    /// they just show kind + duration. Empty when there are no sessions.
    static func sessionLines(_ sessions: [WorkoutSession],
                             exercises: [ExerciseEntry],
                             limit: Int = 5,
                             exerciseLimit: Int = 8,
                             now: Date = .now,
                             calendar: Calendar = .current) -> [String] {
        guard !sessions.isEmpty else { return [] }
        let sorted = sessions.sorted { $0.date > $1.date }
        let startToday = calendar.startOfDay(for: now)
        let yesterday = calendar.date(byAdding: .day, value: -1, to: startToday)
        // Group exercises by session once, so each line is a cheap dictionary lookup.
        let bySession = Dictionary(grouping: exercises, by: { $0.sessionID })

        var out = sorted.prefix(limit).map { s -> String in
            let day = calendar.startOfDay(for: s.date)
            let when: String
            if calendar.isDate(day, inSameDayAs: startToday) { when = "Today" }
            else if let y = yesterday, calendar.isDate(day, inSameDayAs: y) { when = "Yesterday" }
            else { when = Self.weekdayDate.string(from: day) }

            var line = "\(when) — \(s.kind.label)"
            if !s.focuses.isEmpty {
                line += " (\(s.focuses.map { $0.label }.joined(separator: ", ")))"
            }
            if s.durationMinutes > 0 { line += ", \(s.durationMinutes) min" }

            // The machines she trained — catalog order (the same tidy order the day-detail uses), then
            // capped with a "+N more" tail.
            let entries = (bySession[s.id] ?? []).sorted {
                (MachineCatalog.catalogIndex[$0.machineKey] ?? Int.max)
                    < (MachineCatalog.catalogIndex[$1.machineKey] ?? Int.max)
            }
            if !entries.isEmpty {
                line += ", \(entries.count) exercise\(entries.count == 1 ? "" : "s"): "
                var parts = entries.prefix(exerciseLimit).map { exerciseDetail($0) }
                if entries.count > exerciseLimit { parts.append("+\(entries.count - exerciseLimit) more") }
                line += parts.joined(separator: ", ")
            }
            let notes = s.notes.trimmingCharacters(in: .whitespacesAndNewlines)
            if !notes.isEmpty { line += " — \(trimmedNote(notes, max: 200))" }
            return line
        }
        if sorted.count > limit {
            let extra = sorted.count - limit
            out.append("…and \(extra) more session\(extra == 1 ? "" : "s")")
        }
        return out
    }

    /// One exercise rendered for `sessionLines`: "Chest press 90lb 3x10" (name + working weight if
    /// set + sets×reps). Weight is dropped when unset (0), matching the day-detail's "—".
    private static func exerciseDetail(_ e: ExerciseEntry) -> String {
        let raw = e.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = raw.isEmpty ? (MachineCatalog.machine(for: e.machineKey)?.name ?? "Exercise") : raw
        var s = name
        if e.weightLbs > 0 { s += " \(Int(e.weightLbs.rounded()))lb" }
        if e.sets > 0 && e.reps > 0 { s += " \(e.sets)x\(e.reps)" }
        return s
    }

    /// One compact line per logged item: "Name ×qty (Meal) — X kcal, Pg / Cg / Fg", with the
    /// item's serving, calorie range, source/confidence, and — crucially — the AI's own component
    /// breakdown/assumptions from `notes` appended to the SAME line. THAT detail is what lets Vita
    /// answer "what are the +3 more items?" for a combined meal like a fast-food order, instead of
    /// admitting she can't see the components (the bug this fixes: previously only name + macros
    /// were injected, dropping `notes`/`servingDescription`). One line per item is kept on purpose
    /// (callers/tests rely on it). Newest first, capped at `limit` with a "…and N more" tail so a
    /// heavy day can't blow up the prompt; `notes` is lightly trimmed only if very long so it stays
    /// complete but bounded.
    static func itemLines(_ foods: [FoodEntry], limit: Int = 15) -> [String] {
        let sorted = foods.sorted { $0.date > $1.date }
        var out = sorted.prefix(limit).map { f -> String in
            let raw = f.name.trimmingCharacters(in: .whitespacesAndNewlines)
            let name = raw.isEmpty ? "Unnamed item" : raw
            let qty = f.quantity != 1 ? " ×\(formatQty(f.quantity))" : ""
            var line = "\(name)\(qty) (\(f.mealType.label)) — \(Int(f.totalCalories.rounded())) kcal, "
                + "\(Int(f.totalProteinG.rounded()))g P / \(Int(f.totalCarbsG.rounded()))g C / "
                + "\(Int(f.totalFatG.rounded()))g F"

            // Trailing detail so the FULL meal is visible — serving size, any uncertainty range,
            // how it was logged, and the AI's item-by-item breakdown / assumptions (`notes`).
            var details: [String] = []
            let serving = f.servingDescription.trimmingCharacters(in: .whitespacesAndNewlines)
            if !serving.isEmpty { details.append("serving: \(serving)") }
            if let lo = f.caloriesLow, let hi = f.caloriesHigh, hi > lo {
                // Per-serving range scaled to the logged quantity, matching the totals above.
                details.append("est. range \(Int((lo * f.quantity).rounded()))–\(Int((hi * f.quantity).rounded())) kcal")
            }
            if f.source != .manual {
                details.append("logged via \(f.source.rawValue)\(f.confidence.map { ", \($0.label.lowercased()) confidence" } ?? "")")
            } else if let conf = f.confidence {
                details.append("\(conf.label.lowercased()) confidence")
            }
            let notes = (f.notes ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !notes.isEmpty { details.append("breakdown/notes: \(trimmedNote(notes))") }
            if !details.isEmpty { line += " [" + details.joined(separator: "; ") + "]" }
            return line
        }
        if sorted.count > limit {
            let extra = sorted.count - limit
            out.append("…and \(extra) more item\(extra == 1 ? "" : "s")")
        }
        return out
    }

    /// "Last night's sleep: 7h 24m asleep (1h 20m deep, 1h 45m REM) …" — the stage breakdown
    /// when the tracker reports one, plus a 7-night average when there's enough history.
    /// Nil when there's no sleep data for last night (older nights alone would read stale
    /// as "last night").
    static func lastNightSleepLine(_ sleep: [SleepEntry],
                                   now: Date = .now,
                                   calendar: Calendar = .current) -> String? {
        let today = calendar.startOfDay(for: now)
        guard let lastNight = sleep.first(where: { calendar.isDate($0.date, inSameDayAs: today) }),
              lastNight.asleepMinutes > 0 else { return nil }
        var line = "Last night's sleep: \(hm(lastNight.asleepMinutes)) asleep"
        if lastNight.hasStages {
            var stages: [String] = []
            if lastNight.deepMinutes > 0 { stages.append("\(hm(lastNight.deepMinutes)) deep") }
            if lastNight.remMinutes > 0 { stages.append("\(hm(lastNight.remMinutes)) REM") }
            if lastNight.coreMinutes > 0 { stages.append("\(hm(lastNight.coreMinutes)) core") }
            if lastNight.awakeMinutes > 0 { stages.append("\(hm(lastNight.awakeMinutes)) awake") }
            if !stages.isEmpty { line += " (\(stages.joined(separator: ", ")))" }
        }
        line += " — from her tracker via Apple Health"
        let week = sleep.filter {
            $0.asleepMinutes > 0 && $0.date > calendar.date(byAdding: .day, value: -7, to: today)! && $0.date <= today
        }
        if week.count >= 3 {
            let avg = week.reduce(0) { $0 + $1.asleepMinutes } / week.count
            line += "; ~\(hm(avg)) average over the last \(week.count) nights"
        }
        return line
    }

    /// "Recovery vitals today: resting HR 58 bpm, HRV 46 ms (7-day avg: 60 bpm / 42 ms)".
    /// Uses the most recent day within 3 days (vitals can lag the bridge sync); nil when
    /// there's nothing recent. Values of 0 mean "not reported" and are omitted.
    static func recoveryVitalsLine(_ vitals: [VitalsEntry],
                                   now: Date = .now,
                                   calendar: Calendar = .current) -> String? {
        let today = calendar.startOfDay(for: now)
        guard let cutoff = calendar.date(byAdding: .day, value: -3, to: today) else { return nil }
        let recent = vitals.filter { $0.date >= cutoff && ($0.restingHeartRate > 0 || $0.hrvMs > 0) }
        guard let latest = recent.max(by: { $0.date < $1.date }) else { return nil }
        var parts: [String] = []
        if latest.restingHeartRate > 0 { parts.append("resting HR \(Int(latest.restingHeartRate.rounded())) bpm") }
        if latest.hrvMs > 0 { parts.append("HRV \(Int(latest.hrvMs.rounded())) ms") }
        guard !parts.isEmpty else { return nil }
        let dayLabel = calendar.isDate(latest.date, inSameDayAs: today) ? "today" : "recently"
        var line = "Recovery vitals (\(dayLabel), from her tracker): " + parts.joined(separator: ", ")
        let week = vitals.filter { $0.date > calendar.date(byAdding: .day, value: -7, to: today)! }
        let rhrs = week.map(\.restingHeartRate).filter { $0 > 0 }
        let hrvs = week.map(\.hrvMs).filter { $0 > 0 }
        if rhrs.count >= 3 {
            var avg = "7-day avg: \(Int((rhrs.reduce(0, +) / Double(rhrs.count)).rounded())) bpm"
            if hrvs.count >= 3 { avg += " / \(Int((hrvs.reduce(0, +) / Double(hrvs.count)).rounded())) ms" }
            line += " (\(avg))"
        }
        return line
    }

    /// One compact line per auto-detected workout, newest first, capped:
    /// "Today — Running, 32 min, 280 kcal (Fitbit)". Empty when there are none.
    static func detectedWorkoutLines(_ detected: [DetectedWorkout],
                                     limit: Int = 5,
                                     now: Date = .now,
                                     calendar: Calendar = .current) -> [String] {
        let sorted = detected.sorted { $0.date > $1.date }
        let startToday = calendar.startOfDay(for: now)
        let yesterday = calendar.date(byAdding: .day, value: -1, to: startToday)
        var out = sorted.prefix(limit).map { w -> String in
            let day = calendar.startOfDay(for: w.date)
            let when: String
            if calendar.isDate(day, inSameDayAs: startToday) { when = "Today" }
            else if let y = yesterday, calendar.isDate(day, inSameDayAs: y) { when = "Yesterday" }
            else { when = Self.weekdayDate.string(from: day) }
            var line = "\(when) — \(w.activity), \(w.durationMinutes) min"
            if w.caloriesBurned > 0 { line += ", \(Int(w.caloriesBurned.rounded())) kcal" }
            if !w.sourceName.isEmpty { line += " (\(w.sourceName))" }
            return line
        }
        if sorted.count > limit {
            let extra = sorted.count - limit
            out.append("…and \(extra) more detected workout\(extra == 1 ? "" : "s")")
        }
        return out
    }

    /// Minutes → "7h 24m" (or "45m" under an hour).
    private static func hm(_ minutes: Int) -> String {
        let h = minutes / 60, m = minutes % 60
        if h == 0 { return "\(m)m" }
        return m == 0 ? "\(h)h" : "\(h)h \(m)m"
    }

    /// `FoodEntry.notes` carries the AI's component breakdown + per-item assumptions, which we
    /// want Vita to see in FULL — so the cap is generous and we only trim a runaway note (clipping
    /// on a word boundary, with an ellipsis) so one pathological entry can't dominate the prompt.
    private static func trimmedNote(_ s: String, max: Int = 600) -> String {
        guard s.count > max else { return s }
        let clipped = String(s.prefix(max))
        if let lastSpace = clipped.lastIndex(of: " ") { return String(clipped[..<lastSpace]) + "…" }
        return clipped + "…"
    }

    /// Per-day food totals for the last `days` days that have any food logged, newest first:
    /// "Today — 2,140 kcal, 79 g protein (4 items)". Today/Yesterday are named; older days
    /// show weekday + date. Empty when there's no food history in the window.
    static func weeklyTotalLines(_ foods: [FoodEntry],
                                 days: Int = 7,
                                 now: Date = .now,
                                 calendar: Calendar = .current) -> [String] {
        let startToday = calendar.startOfDay(for: now)
        guard let cutoff = calendar.date(byAdding: .day, value: -(days - 1), to: startToday) else { return [] }

        struct DayAgg { var cals = 0.0; var protein = 0.0; var count = 0 }
        var byDay: [Date: DayAgg] = [:]
        for f in foods {
            let day = calendar.startOfDay(for: f.date)
            guard day >= cutoff, day <= startToday else { continue }
            var a = byDay[day] ?? DayAgg()
            a.cals += f.totalCalories
            a.protein += f.totalProteinG
            a.count += 1
            byDay[day] = a
        }
        let yesterday = calendar.date(byAdding: .day, value: -1, to: startToday)
        return byDay.keys.sorted(by: >).map { day in
            let a = byDay[day] ?? DayAgg()
            let label: String
            if calendar.isDate(day, inSameDayAs: startToday) { label = "Today" }
            else if let y = yesterday, calendar.isDate(day, inSameDayAs: y) { label = "Yesterday" }
            else { label = Self.weekdayDate.string(from: day) }
            return "\(label) — \(Int(a.cals.rounded())) kcal, \(Int(a.protein.rounded())) g protein "
                + "(\(a.count) item\(a.count == 1 ? "" : "s"))"
        }
    }

    private static func formatQty(_ q: Double) -> String {
        q == q.rounded() ? String(Int(q)) : String(format: "%.1f", q)
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
    private static let weekdayDate: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "EEE MMM d"; return f
    }()
}
