import Foundation

/// Builds Vita's chat quick-prompt suggestion chips — the little tappable starters that sit
/// above the input ("Review my day", "How's my week?", …). A couple are FIXED constants that
/// are always present so there's a stable starting point; the rest are personalized to HER
/// recent data so they improve over time, and they refresh every few days (not every open).
///
/// Mirrors `ChecklistPlanService` / `FoodSuggestionService` / `WeeklyReflection` EXACTLY:
/// - Forced tool use for strict JSON, decoded into `[String]` via a `Payload` envelope.
/// - Grounded in the same factual `CoachContext.summary(...)` the coach reasons over (plus her
///   bio + Vita's durable notes), so the chips read like HER ("How's my soccer week going?").
/// - Degrades gracefully: gated on `KeychainStore.hasAPIKey`; on no-key / network / parse /
///   guardrail failure it returns the fixed list and NEVER throws (like `WeeklyReflection`), so
///   the chip row is never empty and the chat never waits on the network.
/// - A light banned-word `sanitize` pass (same approach as `WeeklyReflection.sanitize` /
///   `ChecklistPlanService.isAllowed`) keeps a stray prompt from steering toward restriction.
/// - A per-user, per-few-days `UserDefaults` cache (same idiom as `SmartSuggestionsView`) means
///   one cheap call every couple of days, not one per chat open.
enum CoachPromptService {

    // MARK: - Constants (always present, in order, before any personalized prompts)

    /// The 1–2 stable starters that are ALWAYS shown first, so the row has a dependable anchor
    /// even before (or instead of) any personalized prompts. Kept short — these read as chips.
    static let constants: [String] = ["Review my day", "How's my week?"]

    /// A couple of warm, generic extras appended after the constants in the OFFLINE / fallback
    /// list (no key, or any failure). They're the human-friendly defaults the chat shipped with,
    /// so a no-key user still sees a full, useful row rather than just the two constants.
    static let fixedExtras: [String] = ["I'm feeling discouraged", "Is this enough protein?"]

    /// How many personalized prompts we ask the model for. Small on purpose: the row is
    /// constants + these, and chips compete with her own words — a handful is plenty.
    static let personalizedCount = 3

    /// The synchronous, no-network starter list: the constants plus the generic extras. Used as
    /// the initial value / fallback so the chips are never empty and there's no flash before the
    /// (possibly) personalized set loads. De-duped defensively (case-insensitive) so a constant
    /// and an extra can never collide.
    static func fixedPrompts() -> [String] {
        dedupedAppending(fixedExtras, to: constants)
    }

    // MARK: - System prompt (persona + light guardrails)

    /// The persona + the load-bearing constraints for what makes a GOOD starter chip. Same warm,
    /// anti-restriction ethos as the coach: celebrate progress, teach, never push under-eating.
    static let system = """
    You are Vita, a warm, upbeat wellness companion. Above the chat input you show a few \
    tappable "quick prompt" chips — short starter messages your friend can tap to begin a \
    conversation with you. Given a factual snapshot of her recent data, propose a few \
    PERSONALIZED chips by calling the `suggest_prompts` tool. Return ONLY the tool call — no \
    other text.

    Write each chip in HER voice — it's a message SHE would tap to send to you (e.g. "How did \
    my week go?", "Why am I so tired lately?", "Help me hit my protein", "I crushed leg day"). \
    Make them feel specific to her real life and data: nod to her actual sports / training, her \
    streak, her trend, her protein, her water — whatever's most relevant right now — so the chips \
    feel like they KNOW her, not generic buttons.

    RULES:
    - Keep every chip SHORT — at most about six words. They render as small pills.
    - Give a MIX: a check-in or reflection, a curiosity/question, and an encouragement or vent \
      starter. Vary them so the row feels fresh.
    - This is about showing up, progress, training, fuel, and feelings — NEVER about restricting \
      food, eating less, calorie-counting, fasting, skipping meals, or hitting a number on the \
      scale. No "diet", no "cheat day", no weigh-in framing. Don't make a chip that pushes \
      under-eating; a chip ABOUT eating enough / protein / energy is great.
    - Warm and natural, never clinical. A tasteful emoji at most occasionally; usually none.

    Return \(personalizedCount) chips via the tool.
    """

    // MARK: - Strict JSON schema for the forced tool call

    /// Bounds the output to a few short prompt strings. Strings (not objects) keep it minimal —
    /// a chip is just its text.
    static let schema: [String: Any] = [
        "type": "object",
        "properties": [
            "prompts": [
                "type": "array",
                "minItems": 2,
                "maxItems": 5,
                "items": ["type": "string"],
            ],
        ],
        "required": ["prompts"],
    ]

    /// Decode envelope matching the tool schema.
    private struct Payload: Codable { var prompts: [String] }

    // MARK: - User prompt (pure, goal- and context-aware)

    /// The per-call context turn. Pure (no I/O) so it's trivial to unit-test that the prompts are
    /// actually personalized to her goal + data. Folds in the same factual data summary the coach
    /// uses, plus her own "about me" bio and Vita's durable notes — those last two are what make
    /// a chip read like HER ("How's my soccer week?") and not generic. We also tell the model which
    /// constant chips are ALREADY shown, so it doesn't waste a slot repeating them.
    ///
    /// - Parameters:
    ///   - name: her display name ("" → "your friend").
    ///   - direction: lose / maintain / gain — steers the warm framing.
    ///   - dataSummary: `CoachContext.summary(...)` output (workouts give us her sports; trend,
    ///     streak, protein, water all give the chips something specific to grab onto).
    ///   - bio: `profile.onboardingNote` — her own words about her routine (may be empty).
    ///   - memoryNotes: `CoachMemory.profileNotes` — durable facts Vita remembers (may be empty).
    static func userPrompt(name: String,
                           direction: GoalPace.Direction,
                           dataSummary: String,
                           bio: String,
                           memoryNotes: String) -> String {
        let who = name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "your friend" : name

        let goal: String
        switch direction {
        case .lose:     goal = "She's working toward gentle, sustainable weight loss — keep the chips about progress, training, fuel, and feelings, never about eating less."
        case .maintain: goal = "She's maintaining and locking in habits that keep her feeling good."
        case .gain:     goal = "She's building strength with a steady lean gain — training and recovery matter."
        }

        let trimmedBio = bio.trimmingCharacters(in: .whitespacesAndNewlines)
        let bioPart = trimmedBio.isEmpty
            ? "She hasn't written an about-me note."
            : "A bit about her, in her own words: \"\(trimmedBio)\""

        let trimmedNotes = memoryNotes.trimmingCharacters(in: .whitespacesAndNewlines)
        let notesPart = trimmedNotes.isEmpty
            ? "You don't have durable notes about her yet."
            : "What you remember about her (durable notes — use these to make the chips feel like HER):\n\(trimmedNotes)"

        return """
        Her name: \(who)
        Her goal/feeling: \(goal)

        These starter chips are ALREADY shown, so don't repeat them — make yours different and \
        complementary: \(constants.map { "\"\($0)\"" }.joined(separator: ", ")).

        Her current data (use her recent workouts, trend, streak, protein, and water to make the \
        chips specific to HER):
        \(dataSummary)

        \(bioPart)

        \(notesPart)

        Now propose \(personalizedCount) short, personalized quick-prompt chips via the tool — \
        in her voice, a mix of a check-in, a question, and an encouragement/vent starter. \
        Nothing about restricting food or hitting a number on the scale.
        """
    }

    // MARK: - Make (build context → call model → sanitize → constants + personalized)

    /// The public entry point the view awaits. Returns the FULL chip list to render: the fixed
    /// constants first, then the personalized chips (de-duped against the constants). Serves a
    /// per-few-days `UserDefaults` cache when one exists, so a plain chat re-open never calls the
    /// network. On no-key / any failure / rejected output it returns `fixedPrompts()` — it NEVER
    /// throws and NEVER blocks the chat (same contract as `WeeklyReflection.make`).
    ///
    /// Forced tool use is Anthropic-only in this app (same as `FoodSuggestionService` /
    /// `ChecklistPlanService`), so we construct `AnthropicClient` directly.
    @MainActor
    static func prompts(profile: UserProfile,
                        foods: [FoodEntry],
                        weights: [WeightEntry],
                        sessions: [WorkoutSession],
                        water: [WaterEntry],
                        memory: CoachMemory?,
                        now: Date = .now) async -> [String] {
        let fallback = fixedPrompts()

        // Serve this period's cache if present — the whole point of the few-days bucket is to
        // avoid an LLM call on every chat open. The cache stores ONLY the personalized prompts;
        // we always re-prepend the (cheap, code-owned) constants so a constant change ships
        // immediately without invalidating the cache.
        let key = cacheKey(userId: profile.id, now: now)
        if let cached = readCache(key) {
            return dedupedAppending(cached, to: constants)
        }

        // No key → just the fixed list. (Caching nothing here is deliberate: the moment she adds
        // a key, the next open personalizes — we don't want a no-key bucket to suppress that.)
        guard AIConfig.hasActiveKey else { return fallback }

        do {
            let personalized = try await generate(profile: profile, foods: foods, weights: weights,
                                                  sessions: sessions, water: water, memory: memory)
            guard !personalized.isEmpty else { return fallback }
            writeCache(key, personalized)
            return dedupedAppending(personalized, to: constants)
        } catch {
            return fallback   // never let the chips depend on the network
        }
    }

    /// The bare model call → sanitize pass, returning ONLY the personalized prompt strings (no
    /// constants). Throws on transport / parse failure; `prompts(...)` catches everything. Split
    /// out so the cache/constants policy lives in one place and this stays easy to reason about.
    @MainActor
    static func generate(profile: UserProfile,
                         foods: [FoodEntry],
                         weights: [WeightEntry],
                         sessions: [WorkoutSession],
                         water: [WaterEntry],
                         memory: CoachMemory?) async throws -> [String] {
        let client = try AIClient.makeFull()

        let dataSummary = CoachContext.summary(profile: profile, foods: foods,
                                               weights: weights, water: water, sessions: sessions)
        let prompt = userPrompt(name: profile.name,
                                direction: profile.pace.direction,
                                dataSummary: dataSummary,
                                bio: profile.onboardingNote,
                                memoryNotes: memory?.profileNotes ?? "")

        let content: [[String: Any]] = [AnthropicClient.textBlock(prompt)]

        let dict = try await client.structured(
            system: system,
            userContent: content,
            toolName: "suggest_prompts",
            toolDescription: "Return a few short, personalized quick-prompt chips (in her voice) for the chat input.",
            schema: schema,
            model: AIConfig.coachModel,
            maxTokens: 300          // bounded: a handful of short strings is well under this
        )

        let data = try JSONSerialization.data(withJSONObject: dict)
        let payload: Payload
        do { payload = try JSONDecoder().decode(Payload.self, from: data) }
        catch { throw AIConfig.AIError.decoding(String(describing: error)) }

        return clean(payload.prompts)
    }

    // MARK: - Cleaning / sanitizing (bound + de-dupe + banned-word filter)

    /// Trim, bound, de-dupe, and safety-filter the model's prompt strings: drop empties and
    /// anything that trips a food-restriction / scale banned word, collapse whitespace, cap the
    /// length so a runaway string can't break the pill, de-dupe case-insensitively, and bound the
    /// COUNT so a chatty response can't flood the row. Also drops any that merely re-state a
    /// constant (so we don't show "How's my week?" twice). Returns ONLY the personalized strings.
    static func clean(_ prompts: [String]) -> [String] {
        var seen = Set(constants.map { $0.lowercased() })   // never re-emit a constant
        var out: [String] = []
        for p in prompts {
            let text = boundPrompt(p)
            guard !text.isEmpty, isAllowed(text) else { continue }
            let key = text.lowercased()
            guard seen.insert(key).inserted else { continue }   // de-dupe (and vs. constants)
            out.append(text)
            if out.count >= personalizedCount { break }
        }
        return out
    }

    /// A prompt is allowed unless it reads like food restriction or a scale fixation. Mirrors
    /// `ChecklistPlanService.isAllowed` / `WeeklyReflection.sanitize`: a small, conservative
    /// banned-substring list — the chips are about showing up, progress, fuel, and feelings, never
    /// about eating less or weighing in. Education words ("protein", "energy") are NOT banned.
    static func isAllowed(_ prompt: String) -> Bool {
        let lower = prompt.lowercased()
        let banned = [
            "eat less", "eat fewer", "fewer calorie", "fewer calories", "cut calorie",
            "cut calories", "calorie deficit", "count calorie", "count calories", "restrict",
            "fasting", "skip a meal", "skip meal", "skip breakfast", "skip lunch",
            "skip dinner", "starve", "starving", "diet", "cheat day", "cheat meal",
            "weigh in", "weigh-in", "weigh myself", "weigh yourself", "step on the scale",
            "no eating", "don't eat", "stop eating", "lose weight faster", "barely eat",
        ]
        if banned.contains(where: lower.contains) { return false }
        // "fast" as a WHOLE word — catches "intermittent fast" / "fast day" without ever flagging
        // "breakfast" (a substring check would mis-fire on the end of "breakfast").
        return lower.range(of: "\\bfast\\b", options: .regularExpression) == nil
    }

    /// Trim and bound one prompt so a runaway string can't dominate or break a chip. Collapses
    /// inner whitespace runs to single spaces, strips a wrapping pair of quotes the model
    /// sometimes adds, and caps the length at a chip-friendly size.
    static func boundPrompt(_ raw: String, maxLength: Int = 42) -> String {
        var collapsed = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
        if collapsed.count > 1, collapsed.hasPrefix("\""), collapsed.hasSuffix("\"") {
            collapsed = String(collapsed.dropFirst().dropLast())
                .trimmingCharacters(in: .whitespaces)
        }
        guard collapsed.count > maxLength else { return collapsed }
        return String(collapsed.prefix(maxLength)).trimmingCharacters(in: .whitespaces)
    }

    /// Append `additions` after `base`, dropping any that duplicate (case-insensitively) something
    /// already present. Order-preserving; `base` always comes first. This is how the constants are
    /// guaranteed to lead the row and never be duplicated by a personalized/extra prompt.
    static func dedupedAppending(_ additions: [String], to base: [String]) -> [String] {
        var seen = Set(base.map { $0.lowercased() })
        var out = base
        for a in additions {
            let trimmed = a.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, seen.insert(trimmed.lowercased()).inserted else { continue }
            out.append(trimmed)
        }
        return out
    }

    // MARK: - Period cache (UserDefaults, keyed per user + a ~3-day bucket)

    /// How many days each cache bucket spans. The personalized chips refresh when the bucket
    /// rolls over — so roughly every few days, NOT on every chat open.
    static let bucketDays = 3

    /// The few-days bucket index for a date: `floor(daysSinceReferenceDate / bucketDays)`. Whole
    /// days since the reference date (computed off `timeIntervalSinceReferenceDate`) make this a
    /// stable, timezone-stable integer that advances by one every `bucketDays` days.
    static func periodBucket(_ date: Date = .now) -> Int {
        let days = Int(floor(date.timeIntervalSinceReferenceDate / 86_400))
        return Int(floor(Double(days) / Double(bucketDays)))
    }

    /// The `.task(id:)` key for the view: changes per user AND every time the bucket rolls over,
    /// so SwiftUI re-runs the load (serving the new bucket's cache or generating it) every few
    /// days without a timer. Public so the view can key its `.task` on the exact same value.
    static func periodKey(userId: UUID, now: Date = .now) -> String {
        "\(userId.uuidString)#\(periodBucket(now))"
    }

    /// UserDefaults cache key: "vita.prompts.<userId>.<bucket>". A new user OR a new few-days
    /// bucket is a fresh key, so the personalized set naturally rolls over. (We don't prune old
    /// buckets — each is a tiny array of short strings, and a new bucket simply isn't read.)
    static func cacheKey(userId: UUID, now: Date = .now) -> String {
        "vita.prompts.\(userId.uuidString).\(periodBucket(now))"
    }

    /// Read this bucket's cached PERSONALIZED prompts (constants are not stored — they're
    /// re-prepended live). Nil when absent or empty.
    static func readCache(_ key: String) -> [String]? {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([String].self, from: data),
              !decoded.isEmpty else { return nil }
        return decoded
    }

    /// Cache this bucket's personalized prompts (only the personalized strings, never the
    /// constants). Best-effort — a failed encode just means the next open regenerates.
    static func writeCache(_ key: String, _ prompts: [String]) {
        guard let data = try? JSONEncoder().encode(prompts) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}
