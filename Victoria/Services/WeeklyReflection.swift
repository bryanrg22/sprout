import Foundation

/// The flagship "Weekly Vita Reflection": one warm, AI-written note per week that reasons
/// over the user's last 7 days + onboarding note, shown as a dashboard card.
///
/// Mirrors `OnboardingCoachMessage` / `InsightPhraser`'s safety model EXACTLY:
/// - Optional: only calls the LLM when an API key exists (`KeychainStore.hasAPIKey`);
///   otherwise returns a warm, direction-aware TEMPLATED note. The dashboard NEVER waits
///   on or depends on the network, and this never throws — there is always a note.
/// - Cheap + rare: one short call on the cheap model (`AIConfig.insightModel`), gated to
///   ONCE PER WEEK via UserDefaults. So it's a few cents/user/month at most.
/// - Encouraging + honest (system prompt + light `sanitize`): the model gets only
///   QUALITATIVE facts + a few safe day-counts (e.g. "logged six of seven days") — never a
///   calorie/weight/macro number to invent as a prescription. It CELEBRATES real progress
///   toward the profile's goal (a trend moving the way that goal wants is named and praised)
///   and may offer one small tip. If a losing user's trend dropped very fast, it celebrates
///   the drive, then gently TEACHES why eating enough makes the loss last — educating, never
///   scolding or forbidding. The goal direction comes from the profile, never from the prompt.
///
/// Purely additive: the dashboard's data/targets/persistence are unchanged whether or not
/// this runs.
enum WeeklyReflection {

    // MARK: - Inputs (qualitative only — no numbers the model could prescribe)

    /// Everything Vita is allowed to reflect on, pre-computed by the card from SwiftData.
    /// Deliberately holds NO calorie/weight/macro numbers. The only numbers present are
    /// safe, non-prescriptive *counts out of seven* (days logged, days she ate enough,
    /// goal-hit days) — facts about her consistency, never targets to chase.
    struct Inputs {
        var name: String                       // "" → "friend"
        var direction: GoalPace.Direction      // lose / maintain / gain — drives tone
        var note: String                       // her onboarding free-text (may be empty)

        // Safe counts (0...7). Counts of *days*, never amounts of food/weight.
        var daysLogged: Int                    // days with any log this week
        var ateEnoughDays: Int                 // days she fueled herself well (sufficiency)
        var proteinGoalDays: Int               // days she hit her protein goal
        var waterGoalDays: Int                 // days she hit her water goal
        var stepGoalDays: Int                  // days she hit her step goal
        var workoutDays: Int                   // days she moved her body / trained

        /// Qualitative direction of the SMOOTHED weight trend over the week. We hand the
        /// model the *shape*, never the pounds — and `.droppingFast` is the safety-critical
        /// one: it must pivot to "let's make sure you're fueling enough," never celebrate it.
        var trend: TrendShape
        enum TrendShape { case notEnoughData, steady, easingDown, droppingFast, climbing }
    }

    // MARK: - Public

    /// The week's reflection. Tries the LLM when a key exists; ALWAYS falls back to a warm
    /// template on no-key / network / guardrail rejection. Safe to call from a `Task`.
    /// (Does NOT itself check the once-a-week gate — the caller does that via `isDue`, so
    /// the gate and the data the note is built from stay in lockstep.)
    static func make(_ inputs: Inputs) async -> String {
        let fallback = template(for: inputs)
        guard AIConfig.hasActiveKey else { return fallback }
        return await written(inputs) ?? fallback
    }

    /// The model's note, or nil when the call failed or the guardrail rejected the reply.
    /// Either way `make` shows the template, so both mean "not used".
    static func written(_ inputs: Inputs) async -> String? {
        do {
            let client = try AIClient.make()
            let reply = try await client.chat(
                system: system,
                messages: [ChatTurnMsg(role: "user", text: userPrompt(inputs))],
                model: AIConfig.model(for: .weeklyReflection),   // cheap model — short, warm phrasing
                maxTokens: 420
            )
            let cleaned = sanitize(reply)
            return cleaned.isEmpty ? nil : cleaned
        } catch {
            return nil   // never let the weekly note depend on the network
        }
    }

    // MARK: - System prompt (hard guardrails)

    static let system = """
    You are Vita, a warm, upbeat weight-and-wellness companion writing your friend a short \
    WEEKLY reflection — a "here's what I saw in your week, and I'm proud of you" note. Speak \
    directly to your friend as "you" throughout (never in the third person), use the name \
    once if given, and sound like a caring, fun friend texting — never a clinician or an app. \
    Length: 3 to 5 warm sentences.

    What to do:
    - CELEBRATE real progress toward the goal you are told. If the weight trend moved the way \
    that goal wants, say it plainly and proudly — that's the work paying off. Results matter, \
    so when they're happening, make sure your friend feels it.
    - Also celebrate the wins that drive those results: showing up and logging, eating enough \
    to stay fueled, hitting protein, hydration, movement, consistency.
    - Reflect back the actual week from the facts you're given so your friend feels SEEN.
    - If there is an onboarding note, nod to ONE thing from it so your friend feels known.
    - Be genuinely helpful: it's great to drop ONE small, encouraging tip that keeps the \
    momentum going (protein keeps you full, steps add up, sleep helps recovery, etc.).
    - End warm and forward-looking: you're in this together and next week builds on this one.

    Keep it healthy, never preachy:
    - Follow the guidance on the trend line you are given, and the goal rule beside it. When \
    that line asks you to teach why easing off a little wins: losing too fast usually means \
    under-eating, which burns muscle, tanks energy, and tends to rebound; the goal is still \
    reached by eating enough, keeping protein up, and staying consistent. Encourage and \
    inform — never scold, shame, or forbid.
    - Don't shame any food or anyone's body, and don't pile on guilt or pressure.
    - Don't invent specific calorie, macro, weight, or BMI numbers as advice — speak in warm, \
    plain language. (Saying how many days something happened is great — it celebrates \
    consistency.) At most one tasteful emoji.

    Output only the note (3–5 sentences). No headers, no lists, no bullet points.
    """

    /// The user turn: only the safe, qualitative facts + her note. No numbers to prescribe.
    static func userPrompt(_ i: Inputs) -> String {
        let name = displayName(i.name)

        let goal: String
        switch i.direction {
        case .lose:     goal = "Working toward losing weight, and really wants to SEE results — celebrate them whenever they show."
        case .maintain: goal = "Holding steady, and locking in the habits that feel good."
        case .gain:     goal = "Building strength — a steady, lean gain."
        }

        // Qualitative "how was the week" lines from the safe counts.
        var facts: [String] = []
        facts.append("Logged \(countPhrase(i.daysLogged)) of the last 7 days.")
        if i.ateEnoughDays > 0 {
            facts.append("Fueled well (ate enough) on \(countPhrase(i.ateEnoughDays)) of those days — that's how the results keep coming.")
        }
        if i.proteinGoalDays > 0 { facts.append("Reached the protein goal on \(countPhrase(i.proteinGoalDays)) days.") }
        if i.waterGoalDays > 0   { facts.append("Hit the water goal on \(countPhrase(i.waterGoalDays)) days.") }
        if i.stepGoalDays > 0    { facts.append("Reached the step goal on \(countPhrase(i.stepGoalDays)) days.") }
        if i.workoutDays > 0     { facts.append("Trained / moved on \(countPhrase(i.workoutDays)) days.") }

        return """
        Name: \(name)
        Goal/feeling: \(goal)
        Goal rule: \(GoalFraming.protectiveRule(i.direction))

        The week (qualitative — these are the ONLY facts; do not invent others):
        - \(facts.joined(separator: "\n        - "))
        - \(trendLine(i))

        \(notePart(i))

        Write the weekly reflection now, to \(name) as "you" — celebrate the real progress and follow the guidance above.
        """
    }

    /// What the smoothed trend did, with how to read it FOR THIS GOAL: a drop is progress
    /// only for someone losing, and a climb only for someone gaining.
    static func trendLine(_ i: Inputs) -> String {
        switch i.trend {
        case .notEnoughData:
            return "There isn't enough weigh-in data this week to read a weight trend yet — reflect the week warmly and gently encourage a few weigh-ins so you can show the progress."
        case .steady:
            return i.direction == .maintain
                ? "The smoothed weight trend held steady this week — exactly the goal. Celebrate it."
                : "The smoothed weight trend held steady this week — a normal plateau. Reassure that plateaus are normal and consistency breaks them, and keep the motivation up."
        case .easingDown:
            switch i.direction {
            case .lose:     return "The smoothed weight trend eased DOWN this week — real, sustainable progress. CELEBRATE it warmly; this is exactly what's working."
            case .maintain: return "The smoothed weight trend eased down a little this week — frame this warmly as normal day-to-day fluctuation, never as a problem."
            case .gain:     return "The smoothed weight trend eased down a little this week, which is not the direction of a gain goal — frame it warmly as normal fluctuation, and encourage eating enough to fuel the training. Never a setback."
            }
        case .droppingFast:
            return i.direction == .lose
                ? "The smoothed weight trend dropped VERY fast this week. Celebrate the drive — then gently teach that easing off a little (eating enough, protein, consistency) protects energy and muscle and makes the loss actually last. Encourage and inform, never scold."
                : "The smoothed weight trend dropped quickly this week, which is not what this goal is after. No alarm and no scolding: gently teach that eating enough (and enough protein) is what protects energy and muscle, and encourage it."
        case .climbing:
            return i.direction == .gain
                ? "The smoothed weight trend climbed this week, which is right on track for the lean-gain goal — celebrate the strength being built."
                : "The smoothed weight trend ticked up a little this week — frame this warmly as normal day-to-day fluctuation (water, food, hormones), never as a setback."
        }
    }

    static func notePart(_ i: Inputs) -> String {
        let trimmedNote = i.note.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedNote.isEmpty
            ? "No onboarding note was shared — just reflect the week warmly."
            : "The onboarding note, in \(displayName(i.name))'s own words: \"\(trimmedNote)\""
    }

    // MARK: - Templated fallback (no key / any failure / rejected output)

    /// A warm, direction-aware weekly note that needs no network. Leads with her strongest
    /// non-scale win, nods to her onboarding note when she gave one, handles a fast drop with
    /// a fueling nudge, and always ends with the required medical-professional line.
    static func template(for i: Inputs) -> String {
        let name = displayName(i.name)

        // 1) LEAD with the best non-scale win we can find this week.
        let lead: String
        if i.daysLogged >= 6 {
            lead = "\(name), you showed up almost every day this week — checking in \(countPhrase(i.daysLogged)) times. That consistency is the whole game, and I'm proud of you. 💛"
        } else if i.ateEnoughDays >= 3 {
            lead = "\(name), you fueled yourself well on \(countPhrase(i.ateEnoughDays)) days this week — eating enough is exactly how you feel your best, and it's a real win."
        } else if i.proteinGoalDays >= 3 {
            lead = "\(name), you reached your protein on \(countPhrase(i.proteinGoalDays)) days this week — that's what keeps you strong and steady. Nice work."
        } else if i.workoutDays >= 2 {
            lead = "\(name), you moved your body \(countPhrase(i.workoutDays)) days this week — every bit of that counts and adds up."
        } else if i.daysLogged >= 1 {
            lead = "\(name), you checked in this week, and that matters more than being perfect. Showing up at all is a win worth celebrating. 💛"
        } else {
            lead = "\(name), a fresh week is a fresh page — whenever you're ready to check in, I'm right here with you, no pressure at all. 💛"
        }

        // 2) A gentle middle that's safe for the weight trend (fast drop → fuel up), read
        // for THIS goal: a drop is progress only for someone losing, steady is the goal for
        // someone maintaining. The losing user's wording is unchanged.
        let middle: String
        switch i.trend {
        case .droppingFast:
            middle = i.direction == .lose
                ? "Your trend dropped fast this week — I love the drive! One friendly heads-up: losing this quickly usually means you're not eating quite enough, which can cost you energy and muscle and tends to bounce back. Eat enough to fuel yourself and keep your protein up — you'll still hit your goal, and it'll actually stick."
                : "Your trend dipped quickly this week. One friendly heads-up: that usually means you're not eating quite enough, which can cost you energy and muscle. Eat enough to fuel yourself and keep your protein up — that's what gets you where you're going."
        case .easingDown:
            switch i.direction {
            case .lose:
                middle = "And your trend is easing down — that's real progress, and the sustainable kind that lasts. It's working, so keep doing exactly what you're doing."
            case .maintain:
                middle = "The scale dipped a touch this week, but that's just normal day-to-day noise — water, food, hormones. The long trend is what counts, so don't sweat it."
            case .gain:
                middle = "The scale dipped a touch this week — normal day-to-day noise, nothing lost. Eating enough to fuel your training is what moves it back the way you want."
            }
        case .steady:
            middle = i.direction == .maintain
                ? "The scale held steady this week — which is exactly the goal. Nicely done."
                : "The scale held steady this week, which is totally normal — plateaus happen, and they usually break when you stay consistent. Keep going; it's coming."
        case .climbing:
            middle = i.direction == .gain
                ? "Your trend is climbing right on track for the strength you're building — lovely steady progress."
                : "The scale ticked up a touch this week, but that's just normal day-to-day noise — water, food, hormones. The long trend is what counts, so don't sweat it."
        case .notEnoughData:
            middle = "We don't have quite enough weigh-ins to read your trend yet — hop on the scale a couple times next week and I'll show you how it's moving."
        }

        // 3) Nod to her onboarding note when she gave one; warm close either way.
        let trimmedNote = i.note.trimmingCharacters(in: .whitespacesAndNewlines)
        let close = trimmedNote.isEmpty
            ? "Next week is a fresh page — we'll keep it gentle and take it one small step at a time, together."
            : "I'm keeping what you shared with me close, and we'll keep shaping this around your real life — gently, one small step at a time, together."

        return [lead, middle, close].joined(separator: " ")
    }

    // MARK: - Sanitizer (light net for genuinely harmful output)

    /// Trim/validate the model output. Rejects (→ "", caller uses the warm template) only
    /// genuinely harmful output: phrasing that pushes real under-eating/shame, or a fabricated
    /// number presented as advice. Educational, celebratory, and progress-naming language all
    /// pass — Vita is meant to teach and to celebrate her results.
    static func sanitize(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("\"") && s.hasSuffix("\"") && s.count > 1 {
            s = String(s.dropFirst().dropLast())
        }
        guard !s.isEmpty else { return "" }

        let lower = s.lowercased()

        // Only clearly harmful restriction / shame phrasing → reject (use the safe template).
        // Deliberately NOT banning teaching words like "deficit"/"restrict"/"cut calories" —
        // Vita is supposed to explain those honestly and show healthier ways.
        let banned = [
            "eat less", "eat fewer", "barely eat", "stop eating", "skip a meal", "skip meals",
            "starve", "starving", "crash diet", "purge", "lose faster", "lose weight faster",
            "tiny portion", "smaller portion", "guilt", "guilty", "ashamed", "hate your body"
        ]
        if banned.contains(where: lower.contains) { return "" }

        // A fabricated number presented as advice is the one thing to guard: we never hand the
        // model a calorie/weight/macro figure, so it shouldn't invent one. Our own facts are
        // phrased as words ("six of seven days"), so a healthy note carries no digits.
        if s.rangeOfCharacter(from: .decimalDigits) != nil { return "" }

        // Runaway length → fall back (a weekly note should be a few sentences, not an essay).
        if s.count > 900 { return "" }

        return s
    }

    // MARK: - Once-a-week gate (UserDefaults, no LLM, no SwiftData)

    /// UserDefaults key holding the start-of-ISO-week date string of the last shown note.
    private static let lastShownKey = "weeklyReflection.lastShownWeek"

    /// Start of the current week, used as the gate's bucket. Uses the user's calendar with
    /// its locale-defined first weekday (so "this week" matches how she'd think of it).
    private static func startOfThisWeek(_ now: Date = .now,
                                        calendar: Calendar = .current) -> Date {
        calendar.dateInterval(of: .weekOfYear, for: now)?.start
            ?? calendar.startOfDay(for: now)
    }

    private static func weekKey(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }

    /// True when a NEW weekly reflection is due (we haven't shown one this week yet).
    /// The card hides itself entirely when this is false.
    static func isDue(now: Date = .now, calendar: Calendar = .current) -> Bool {
        let thisWeek = weekKey(startOfThisWeek(now, calendar: calendar))
        return UserDefaults.standard.string(forKey: lastShownKey) != thisWeek
    }

    /// Record that this week's reflection has been shown, so it won't reappear until next
    /// week. Call this only after a note has actually been produced and displayed.
    static func markShown(now: Date = .now, calendar: Calendar = .current) {
        let thisWeek = weekKey(startOfThisWeek(now, calendar: calendar))
        UserDefaults.standard.set(thisWeek, forKey: lastShownKey)
    }

    // MARK: - Helpers

    private static func displayName(_ name: String) -> String {
        let t = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? "friend" : t
    }

    /// Words, not digits, for the "n of 7" counts — so a healthy note carries no numerals
    /// (the sanitizer rejects any digit) while still celebrating consistency.
    private static func countPhrase(_ n: Int) -> String {
        let words = ["zero", "one", "two", "three", "four", "five", "six", "seven"]
        return (0...7).contains(n) ? words[n] : "\(n)"
    }
}
