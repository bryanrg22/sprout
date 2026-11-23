import Foundation

/// The once-a-day "Vita noticed" morning brief — the Google-Health-Coach-style note, in
/// Sprout's warm anti-restriction voice.
///
/// Design (from the Google Health / Whoop research pass):
/// - ONE brief per day, generated lazily on first open and CACHED for the day — stability
///   builds trust; it never flickers to a different message on re-open.
/// - Headline (a human observation, ≤1 number) + a 1–2 sentence body carrying ONE insight
///   with evidence against the user's OWN baseline ("your best in three weeks"), never population
///   norms, never a data dump.
/// - Topic picked by a deterministic PRIORITY LADDER in code (same cheap-gate architecture
///   as `DailyInsightEngine`): returning-from-a-gap > milestone > cross-signal connection >
///   quiet-day reassurance > plain warm check-in. The LLM only REPHRASES the chosen topic —
///   it can never invent a correlation we didn't compute.
/// - Never: guilt, daily scale numbers, clinical vocabulary, medical claims from vitals.
/// - Costs at most ONE cheap-model call per day; with no API key the warm template shows
///   as-is (the card works for everyone).
enum DailyBriefService {

    // MARK: - Model

    struct Brief: Codable, Equatable {
        var headline: String
        var body: String
        var topic: String       // Topic.rawValue — for diagnostics/tests
        var dayKey: String      // "yyyy-MM-dd" the brief belongs to
    }

    // MARK: - Signals (computed by the card from SwiftData — the ONLY facts available)

    struct Signals {
        var name: String = ""
        /// Days since the last active log before today (nil = brand-new user).
        var daysAway: Int? = nil
        var streak: Int = 0
        // Last night (tracker via Apple Health), nil when absent.
        var sleepMinutes: Int? = nil
        var deepMinutes: Int? = nil
        var sleepAvgMinutes: Int? = nil     // 7-night avg, only when ≥3 nights
        // Recovery vitals, nil when absent.
        var restingHR: Double? = nil
        var restingHRAvg: Double? = nil     // 7-day avg, only when ≥3 days
        // Yesterday's movement.
        var stepsYesterday: Int? = nil
        var stepsAvg: Int? = nil            // 7-day avg
        var workedOutYesterday: Bool = false
        /// Smoothed weight trend eased down this week (celebrate-only signal — an
        /// unfavorable trend is deliberately NOT a signal; we never lead with it).
        var trendEasedDown: Bool = false
        var proteinGoalYesterday: Bool = false
        // Active travel shift (TravelSignal.current()), nil when not traveling.
        var travelShiftHours: Int? = nil
        var travelShiftDaysAgo: Int? = nil
    }

    enum Topic: String {
        case gapReturn, travel, milestone, crossSignal, quietDay, checkIn
    }

    // MARK: - Priority ladder (pure + testable)

    /// Pick today's ONE topic and its ready-to-show template. Missing metrics simply make
    /// their rungs ineligible — the brief never blocks on (or mentions) absent data.
    static func pick(_ s: Signals) -> (topic: Topic, headline: String, body: String) {
        let name = s.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let hey = name.isEmpty ? "Hey" : "Hey \(name)"

        // 1) Returning after a few quiet days (4–6; a 7+ gap is the WelcomeBackCard's moment).
        if let away = s.daysAway, (4...6).contains(away) {
            return (.gapReturn,
                    "\(hey) — good to see you.",
                    "No catch-up owed. The story just picks up from today — log one thing and we're rolling again.")
        }

        // 1b) Traveling — the body's on a new clock; reframe the next few days BEFORE
        // any other topic could misread jet-lagged sleep or appetite as a problem.
        if let hours = s.travelShiftHours, let daysAgo = s.travelShiftDaysAgo {
            let dir = hours > 0 ? "east" : "west"
            if daysAgo == 0 {
                return (.travel,
                        "New time zone — your body noticed.",
                        "You moved \(abs(hours)) hours \(dir) today. Sleep and appetite usually take a few days to catch up, so keep it simple: water, daylight, and whatever logging feels easy. That's adjusting, not slipping.")
            }
            return (.travel,
                    "Day \(daysAgo + 1) on the new clock.",
                    "A \(abs(hours))-hour \(dir)ward shift takes most bodies a few days to absorb. If sleep looks ragged or hunger feels off-schedule, that's the trip talking — it settles on its own.")
        }

        // 2) Milestone — a result or a real streak, celebrated plainly.
        if s.trendEasedDown {
            return (.milestone,
                    "Your trend eased down this week.",
                    "That's real progress — the sustainable kind. Whatever you're doing, it's working; keep doing exactly that.")
        }
        if s.streak >= 7, s.streak.isMultiple(of: 7) {
            return (.milestone,
                    "\(s.streak) days of showing up in a row.",
                    "Showing up beats being perfect, and you keep showing up. That consistency is the whole game.")
        }

        // 3) Cross-signal connection — effort met by a steady body, or a real repair night.
        if let steps = s.stepsYesterday, let avg = s.stepsAvg, avg > 2000,
           Double(steps) >= Double(avg) * 1.5,
           let rhr = s.restingHR, let rhrAvg = s.restingHRAvg, abs(rhr - rhrAvg) <= 3 {
            return (.crossSignal,
                    "That big day yesterday? Your body barely blinked.",
                    "\(steps.formatted()) steps, and your resting heart rate is holding right at its usual \(Int(rhrAvg.rounded())) — that's what getting fitter looks like from the inside.")
        }
        if let sleep = s.sleepMinutes, let avg = s.sleepAvgMinutes, sleep >= avg + 45 {
            return (.crossSignal,
                    "Your body did real repair work last night.",
                    "\(hoursMinutes(sleep)) asleep — well above your recent usual. Nights like that tend to make the whole day feel easier.")
        }
        if let deep = s.deepMinutes, deep >= 75 {
            return (.crossSignal,
                    "Last night went deep — in the best way.",
                    "\(hoursMinutes(deep)) of deep sleep is your body doing its repair work. Days after nights like that usually just feel better.")
        }

        // 4) Quiet day, reframed as recovery (never as failure).
        if let steps = s.stepsYesterday, let avg = s.stepsAvg, avg > 2000,
           Double(steps) <= Double(avg) * 0.5, !s.workedOutYesterday {
            var body = "Rest is your body cashing in the work you've already done — it counts, not against you."
            if let rhr = s.restingHR, let rhrAvg = s.restingHRAvg, rhr <= rhrAvg {
                body = "Your resting heart rate agrees — it's sitting at \(Int(rhr.rounded())), right where recovery lives. If you feel like moving today, a ten-minute walk absolutely counts."
            }
            return (.quietDay, "Yesterday was a quiet one — and that's fine.", body)
        }

        // 5) Nothing stands out → a plain warm check-in beats a manufactured insight.
        return (.checkIn,
                "\(hey) — I'm here, and today's a fresh page.",
                "Nothing to fix, nothing to chase. One logged meal, one glass of water, one small walk — any of them counts as a win today.")
    }

    // MARK: - Daily cache

    private static let cacheKey = "dailyBrief.v1"   // gitleaks:allow (a UserDefaults key name, not a secret)

    static func dayKey(for date: Date = .now, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    static func cachedBrief(dayKey key: String, defaults: UserDefaults = .standard) -> Brief? {
        guard let data = defaults.data(forKey: cacheKey),
              let brief = try? JSONDecoder().decode(Brief.self, from: data),
              brief.dayKey == key else { return nil }
        return brief
    }

    static func store(_ brief: Brief, defaults: UserDefaults = .standard) {
        if let data = try? JSONEncoder().encode(brief) {
            defaults.set(data, forKey: cacheKey)
        }
    }

    // MARK: - Public entry: cache → template → (optional) one cheap rephrase call

    /// Today's brief. Returns the cached one when it exists; otherwise picks the topic,
    /// optionally warms the phrasing with ONE cheap-model call, caches, and returns.
    /// Never throws, never blocks the dashboard on the network longer than one short call.
    static func todaysBrief(signals: Signals,
                            now: Date = .now,
                            defaults: UserDefaults = .standard) async -> Brief {
        let key = dayKey(for: now)
        if let cached = cachedBrief(dayKey: key, defaults: defaults) { return cached }

        let picked = pick(signals)
        var brief = Brief(headline: picked.headline, body: picked.body,
                          topic: picked.topic.rawValue, dayKey: key)

        // Optional AI polish — same safety model as WeeklyReflection/InsightPhraser: the
        // template is already shippable; the model may only rewarm the SAME fact.
        if AIConfig.hasActiveKey, let polished = await rephrase(picked, name: signals.name) {
            brief.headline = polished.headline
            brief.body = polished.body
        }

        store(brief, defaults: defaults)
        Diagnostics.shared.log("daily brief generated: \(brief.topic)", .ai)
        return brief
    }

    // MARK: - LLM rephrase (cheap model, strict guardrails, template fallback)

    /// Not told the goal direction (the ladder already chose the topic), so the rule about
    /// food is the one for every direction. Nothing here depends on the user or the day.
    private static let system = """
    You are Vita, a warm weight-and-wellness companion writing your friend a short morning \
    note. You are given ONE observation (a headline and a body). Rewrite them in your own warm, \
    specific voice — like a caring friend texting, never a clinician or an app. Speak to your \
    friend directly as "you"; never write about your friend in the third person.

    Hard rules:
    - Keep the SAME single insight and the SAME numbers — never add, change, or invent a number \
    or a new claim.
    - Headline: one short sentence, at most one number. Body: one or two sentences.
    - Never guilt, shame, restriction talk, daily scale numbers, or medical claims. Never \
    describe eating as excessive. Rest days are good. Food is fuel. At most one tasteful emoji.
    Reply with the headline on the FIRST line and the body on the following line(s). No labels.
    """

    /// The user turn: who the note is for and the observation to rewarm. Pure.
    static func userTurn(_ picked: (topic: Topic, headline: String, body: String), name: String) -> String {
        """
        Your friend's name: \(name.isEmpty ? "friend" : name)
        The observation to rewarm (keep its meaning and numbers exactly):
        Headline: \(picked.headline)
        Body: \(picked.body)
        """
    }

    static func rephrase(_ picked: (topic: Topic, headline: String, body: String),
                                 name: String) async -> (headline: String, body: String)? {
        guard let reply = await rephraseRaw(picked, name: name) else { return nil }
        if let reason = rejection(of: reply) {
            // The template is already on screen, so this is silent to the user; the trace is
            // what makes "why is the brief never rewritten" answerable from a device.
            Diagnostics.shared.log("daily brief rewrite discarded (\(picked.topic.rawValue)): \(reason)", .ai)
        }
        return parse(reply)
    }

    /// The model's reply as it came back, before the guardrail; nil when the call failed.
    static func rephraseRaw(_ picked: (topic: Topic, headline: String, body: String),
                            name: String) async -> String? {
        do {
            let client = try AIClient.make()
            return try await client.chat(system: system,
                                         messages: [ChatTurnMsg(role: "user", text: userTurn(picked, name: name))],
                                         model: AIConfig.model(for: .dailyBrief),
                                         maxTokens: 160)
        } catch {
            return nil   // template already shipped — silent fallback
        }
    }

    static let bannedPhrases = ["eat less", "eat fewer", "barely eat", "stop eating", "skip a meal",
                                "skip meals", "starve", "crash diet", "guilt", "guilty", "ashamed",
                                "make up for", "burn off", "cheat"]

    /// Why `parse` would throw this reply away, or nil if it would keep it.
    static func rejection(of raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "empty" }
        if trimmed.count > 500 { return "longer than 500 characters" }
        let lower = trimmed.lowercased()
        if let phrase = bannedPhrases.first(where: lower.contains) { return "contains \"\(phrase)\"" }
        if headlineAndBody(trimmed).body.isEmpty { return "no body after the headline" }
        return nil
    }

    /// First line → headline, remainder → body; rejects harmful phrasing or runaway length.
    ///
    /// Models do not always put the line break in. A reply on ONE line with two or more
    /// sentences is split at the end of its first sentence rather than thrown away: that
    /// one formatting slip was discarding a paid, otherwise good rewrite (EVAL_REPORT 14).
    static func parse(_ raw: String) -> (headline: String, body: String)? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard rejection(of: trimmed) == nil else { return nil }
        let parts = headlineAndBody(trimmed)
        return parts.body.isEmpty ? nil : parts
    }

    /// Splits a reply into its headline and body: by line when there is more than one line,
    /// otherwise at the end of the first sentence. The body is empty when there is none.
    static func headlineAndBody(_ trimmed: String) -> (headline: String, body: String) {
        let lines = trimmed.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
        guard let first = lines.first else { return ("", "") }
        let rest = lines.dropFirst().joined(separator: " ").trimmingCharacters(in: .whitespaces)
        if !rest.isEmpty { return (first.trimmingCharacters(in: .whitespaces), rest) }

        // One line: the first sentence is the headline.
        var firstSentenceEnd: String.Index?
        first.enumerateSubstrings(in: first.startIndex..., options: .bySentences) { _, range, _, stop in
            firstSentenceEnd = range.upperBound
            stop = true
        }
        guard let end = firstSentenceEnd, end < first.endIndex else { return (first, "") }
        let headline = first[..<end].trimmingCharacters(in: .whitespaces)
        let body = first[end...].trimmingCharacters(in: .whitespaces)
        // A "body" with no letters (a trailing emoji) is not a body.
        guard body.contains(where: \.isLetter) else { return (first, "") }
        return (headline, body)
    }

    // MARK: - Helpers

    static func hoursMinutes(_ minutes: Int) -> String {
        let h = minutes / 60, m = minutes % 60
        if h == 0 { return "\(m)m" }
        return m == 0 ? "\(h)h" : "\(h)h \(m)m"
    }
}
