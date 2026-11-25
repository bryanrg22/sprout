import Foundation

/// One AI-proposed checklist entry — either a morning *task* Vita suggests for today, or a
/// personalized quick-add *chip*. Deliberately the same shape as `ChecklistSuggestion`
/// (title + SF Symbol), but `Codable`/`Identifiable`/`Hashable` so a whole plan can be
/// cached in `UserDefaults` and dropped straight into `ForEach`.
///
/// The `id` is synthesized (NOT part of the wire schema) so a cached plan keeps stable
/// identities across decodes; only `title` + `icon` cross the model boundary.
struct ChecklistProposal: Codable, Identifiable, Hashable {
    var id = UUID()
    /// A short, tappable label ("Soccer", "Leg day", "Evening walk").
    var title: String
    /// An SF Symbol name, validated against `ChecklistPlanService.allowedIcons`.
    var icon: String

    /// Only `title` + `icon` are encoded/decoded; `id` is synthesized so cached plans stay
    /// stable. Decoding tolerates a missing field by reading it as empty (the caller cleans).
    enum CodingKeys: String, CodingKey { case title, icon }

    init(id: UUID = UUID(), title: String, icon: String) {
        self.id = id; self.title = title; self.icon = icon
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = UUID()
        title = (try? c.decode(String.self, forKey: .title)) ?? ""
        icon = (try? c.decode(String.self, forKey: .icon)) ?? "checklist"
    }
}

/// A full, personalized "Today's checklist" plan: a few proposed morning tasks Vita offers
/// (accepted with one tap), plus a set of quick-add chips drawn from the activities SHE
/// actually does. `Equatable` for `.task(id:)`-style change checks; `Codable` for the
/// per-day `UserDefaults` cache.
struct ChecklistPlan: Codable, Equatable {
    var tasks: [ChecklistProposal]
    var chips: [ChecklistProposal]
}

/// Builds Vita's personalized "Today's checklist": she proposes a few warm morning
/// intentions AND quick-add chips drawn from the person's goal + recent training + life
/// context (so a soccer player sees "Soccer", a lifter sees "Leg day").
///
/// Mirrors `FoodSuggestionService` / `WeeklyReflection` EXACTLY:
/// - Forced tool use for strict JSON, decoded into `ChecklistPlan` via a `Payload` envelope.
/// - Numbers stay code-owned: the model only writes movement/rest/prep/wellness words. The
///   system prompt bans food-restriction and scale framing outright (same ethos as
///   `ChecklistItem`), and a `sanitize`/icon-validation pass is the safety net on output.
/// - Degrades gracefully: the caller gates on `KeychainStore.hasAPIKey` and falls back to
///   `fallback()` (the static presets) on no-key / network / parse / guardrail failure.
enum ChecklistPlanService {

    // MARK: - System prompt (persona + hard guardrails)

    /// The persona + the load-bearing constraint. Kept separate from the per-call context so
    /// it's easy to read against the anti-restriction tone. Same ethos as `ChecklistItem`:
    /// ONLY movement / rest / prep / wellness — NEVER food restriction or a number on the scale.
    static let system = """
    You are Vita, a warm, upbeat wellness companion planning your friend's day. Given a \
    factual snapshot of your friend's goal, recent training, and a bit about your friend's \
    life, propose a short "Today's checklist" by calling the `plan_checklist` tool. Return \
    ONLY the tool call — no other text.

    Two things to return:
    - `tasks`: 3 to 5 gentle intentions for TODAY — the few things you'd lovingly nudge your \
      friend to do. Make them feel like a caring friend's plan, specific to THIS person (name \
      the actual sports / training split when you can tell what they are, e.g. "Leg day at \
      the gym", "Soccer practice", "Evening run"). Each is a short doable action.
    - `chips`: 4 to 8 quick-add buttons of activities your friend ACTUALLY does, so adding to \
      the day is one tap. Pull these from the real routine (the logged workouts, what you've \
      been told). Include a couple of universal ones (a walk, an early night) so the row \
      never feels empty.

    HARD RULES — this list is about SHOWING UP, never about food or the scale:
    - ONLY movement, rest, recovery, prep, and wellness ("Gym", "Soccer", "Leg day", "Yoga", \
      "Evening walk", "Stretch", "Meal prep", "8 hours of sleep", "Drink water", "10 min walk").
    - NEVER anything about restricting food, eating less, calories, fasting, skipping meals, \
      weighing in, or hitting a number on the scale. No "diet", no "cheat day", no weigh-ins.
    - Warm and encouraging, never a drill sergeant. Keep every title SHORT (2–4 words is ideal).

    For each task and chip, give a short `title` and a single `icon` that is an EXACT Apple \
    SF Symbol name (e.g. "figure.run", "dumbbell.fill", "figure.soccer", "bed.double.fill", \
    "figure.walk", "sportscourt.fill"). If you're unsure of the exact symbol, use "checklist".
    """

    // MARK: - Strict JSON schema for the forced tool call

    /// Bounds the output to a sane plan: 3–5 tasks, 4–8 chips, each `{title, icon}` required.
    static let schema: [String: Any] = [
        "type": "object",
        "properties": [
            "tasks": [
                "type": "array",
                "minItems": 3,
                "maxItems": 5,
                "items": [
                    "type": "object",
                    "properties": [
                        "title": ["type": "string"],
                        "icon": ["type": "string"],
                    ],
                    "required": ["title", "icon"],
                ],
            ],
            "chips": [
                "type": "array",
                "minItems": 4,
                "maxItems": 8,
                "items": [
                    "type": "object",
                    "properties": [
                        "title": ["type": "string"],
                        "icon": ["type": "string"],
                    ],
                    "required": ["title", "icon"],
                ],
            ],
        ],
        "required": ["tasks", "chips"],
    ]

    /// Decode envelope matching the tool schema.
    private struct Payload: Codable { var tasks: [ChecklistProposal]; var chips: [ChecklistProposal] }

    // MARK: - User prompt (pure, goal- and context-aware)

    /// The per-call context turn. Pure (no I/O) so it's trivial to unit-test that the plan is
    /// actually personalized to her goal + data. Folds in the same factual data summary the
    /// coach uses, plus her own "about me" bio and Vita's durable qualitative notes — those
    /// last two are what make the chips read like HER ("Soccer", "Leg day") and not generic.
    ///
    /// - Parameters:
    ///   - name: her display name ("" → "your friend").
    ///   - direction: lose / maintain / gain — steers the warm framing.
    ///   - dataSummary: `CoachContext.summary(...)` output (workouts give us her sports).
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
        case .lose:     goal = "Working toward gentle, sustainable weight loss — keep the plan about movement and showing up, never about eating less."
        case .maintain: goal = "Maintaining, and locking in the habits that feel good."
        case .gain:     goal = "Building strength with a steady lean gain — training and recovery matter."
        }

        let trimmedBio = bio.trimmingCharacters(in: .whitespacesAndNewlines)
        let bioPart = trimmedBio.isEmpty
            ? "\(who) hasn't written an about-me note."
            : "A bit about \(who), in \(who)'s own words: \"\(trimmedBio)\""

        let trimmedNotes = memoryNotes.trimmingCharacters(in: .whitespacesAndNewlines)
        let notesPart = trimmedNotes.isEmpty
            ? "You don't have durable notes about \(who) yet."
            : "What you remember about \(who) (durable notes — use these to make the chips feel personal):\n\(trimmedNotes)"

        return """
        Name: \(who)
        Goal/feeling: \(goal)
        Goal rule: \(GoalFraming.protectiveRule(direction))

        Current data for \(who) (use the recent workouts to spot the sports / training split \
        actually done — those should become tasks and chips):
        \(dataSummary)

        \(bioPart)

        \(notesPart)

        Now propose today's checklist via the tool: 3–5 warm tasks for today and 4–8 quick-add \
        chips of activities \(who) actually does. Movement / rest / prep / wellness only — nothing \
        about food or the scale.
        """
    }

    // MARK: - Allowed SF Symbols (validated against the model's output)

    /// The icons we trust to render. Built from the existing checklist presets + every
    /// `WorkoutType` / `MealType` glyph, plus a curated set of common movement / rest /
    /// wellness symbols Vita is likely to reach for. Anything the model returns that ISN'T
    /// here falls back to "checklist", so an invented/typo'd symbol can never show a blank box.
    static let allowedIcons: Set<String> = {
        var icons: Set<String> = ["checklist"]
        // The offline presets (Gym/Run/Walk/Yoga/Stretch/Meal prep/Sleep early).
        for s in ChecklistSuggestion.all { icons.insert(s.systemIcon) }
        // Every workout-type and meal-type glyph the app already ships.
        for t in WorkoutType.allCases { icons.insert(t.systemImage) }
        for m in MealType.allCases { icons.insert(m.systemImage) }
        // Curated extras: activities/rest/prep/wellness Vita commonly suggests. All verified
        // SF Symbols that exist on the app's deployment target.
        icons.formUnion([
            "figure.run", "figure.walk", "figure.hiking", "figure.yoga",
            "figure.flexibility", "figure.strengthtraining.traditional",
            "figure.strengthtraining.functional", "figure.cooldown",
            "figure.core.training", "figure.mind.and.body", "figure.dance",
            "figure.pool.swim", "figure.open.water.swim", "figure.outdoor.cycle",
            "figure.indoor.cycle", "figure.elliptical", "figure.rower",
            "figure.jumprope", "figure.boxing", "figure.kickboxing",
            "figure.martial.arts", "figure.climbing", "figure.pilates",
            "figure.soccer", "figure.basketball", "figure.tennis",
            "figure.volleyball", "figure.baseball", "figure.golf",
            "figure.badminton", "figure.table.tennis", "figure.hockey",
            "figure.cross.training", "figure.mixed.cardio", "figure.stairs",
            "figure.barre", "figure.surfing", "figure.skiing.downhill",
            "dumbbell.fill", "sportscourt.fill", "tennis.racket", "soccerball",
            "basketball.fill", "volleyball.fill", "bicycle",
            "bed.double.fill", "moon.zzz.fill", "moon.stars.fill", "powersleep",
            "drop.fill", "carrot.fill", "fork.knife", "leaf.fill",
            "heart.fill", "bolt.fill", "sun.max.fill", "sunrise.fill",
            "wind", "shoeprints.fill", "book.fill", "brain.head.profile",
        ])
        return icons
    }()

    // MARK: - Make (build context → call model → validate → decode)

    /// Generate the day's personalized plan. Throws `AIConfig.AIError.missingKey` when no key
    /// is configured (the caller gates on `AIConfig.hasActiveKey` first, but we surface it
    /// cleanly anyway), and `.badResponse` / `.decoding` on transport / parse failures. The
    /// CARD never lets this throw past it — it catches everything and keeps `fallback()`.
    ///
    /// Provider-aware: forced tool use runs on either vendor via `AIClient.makeFull()`.
    @MainActor
    static func make(profile: UserProfile,
                     foods: [FoodEntry],
                     weights: [WeightEntry],
                     sessions: [WorkoutSession],
                     water: [WaterEntry],
                     memory: CoachMemory?) async throws -> ChecklistPlan {
        let client = try AIClient.makeFull()

        // Pass the user's real Workouts-tab sessions through the `sessions` channel — the legacy
        // `workouts: [WorkoutEntry]` arg never carried real data, so the plan couldn't see training.
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
            toolName: "plan_checklist",
            toolDescription: "Return today's personalized checklist: a few warm tasks plus quick-add chips of activities the user actually does.",
            schema: schema,
            model: AIConfig.model(for: .checklistPlan),
            maxTokens: 700          // bounded: a handful of short tasks + chips is well under this
        )

        return try plan(fromToolInput: dict)
    }

    /// The plan the card shows for a tool call's input (already repaired by the client):
    /// decoded, then cleaned. Pure, so an evaluation can rebuild what was shown from a
    /// recorded reply.
    static func plan(fromToolInput dict: [String: Any]) throws -> ChecklistPlan {
        let data = try JSONSerialization.data(withJSONObject: dict)
        let payload: Payload
        do { payload = try JSONDecoder().decode(Payload.self, from: data) }
        catch { throw AIConfig.AIError.decoding(String(describing: error)) }

        let tasks = clean(payload.tasks, max: 5)
        let chips = clean(payload.chips, max: 8)
        // If sanitizing emptied both lists (a fully off-tone response), surface a decode error
        // so the card keeps its safe fallback rather than rendering a blank plan.
        guard !tasks.isEmpty || !chips.isEmpty else { throw AIConfig.AIError.decoding("no valid checklist items") }
        return ChecklistPlan(tasks: tasks, chips: chips)
    }

    // MARK: - Fallback (no key / any failure / rejected output)

    /// The documented offline plan: NO proposed tasks (we never auto-suggest without the
    /// model), and the static presets as quick-add chips — exactly today's behavior.
    static func fallback() -> ChecklistPlan {
        ChecklistPlan(tasks: [], chips: ChecklistSuggestion.all.map { ChecklistProposal($0) })
    }

    // MARK: - Cleaning / sanitizing (icon validation + banned-word filter)

    /// Trim, bound, de-dupe, and safety-filter a list of proposals: validate each `icon`
    /// against `allowedIcons` (unknown → "checklist"), bound the title length, drop empties,
    /// and drop anything whose title trips a food-restriction banned word. Caps the result at
    /// `max` so a runaway response can't flood the UI.
    static func clean(_ proposals: [ChecklistProposal], max: Int) -> [ChecklistProposal] {
        var seen = Set<String>()
        var out: [ChecklistProposal] = []
        for p in proposals {
            let title = boundTitle(p.title)
            guard !title.isEmpty, isAllowed(title) else { continue }
            // De-dupe case-insensitively so the model can't repeat the same chip.
            let key = title.lowercased()
            guard seen.insert(key).inserted else { continue }
            out.append(ChecklistProposal(title: title, icon: validIcon(p.icon)))
            if out.count >= max { break }
        }
        return out
    }

    /// A title is allowed unless it reads like food restriction or a scale fixation. Mirrors
    /// `WeeklyReflection.sanitize`'s approach: a small, conservative banned-substring list —
    /// this list is about SHOWING UP, never about eating less or weighing in.
    static func isAllowed(_ title: String) -> Bool {
        let lower = title.lowercased()
        let banned = [
            "eat less", "eat fewer", "fewer calorie", "fewer calories", "cut calorie",
            "cut calories", "calorie deficit", "count calorie", "restrict",
            "fasting", "skip a meal", "skip meal", "skip breakfast", "skip lunch",
            "skip dinner", "starve", "starving", "diet", "cheat day", "cheat meal",
            "weigh in", "weigh-in", "weigh yourself", "step on the scale", "no eating",
            "don't eat", "stop eating", "lose weight",
        ]
        if banned.contains(where: lower.contains) { return false }
        // "fast" as a WHOLE word — catches "intermittent fast" / "fast day" without ever flagging
        // "breakfast" (the old "fast " substring missed an end-of-string "fast").
        return lower.range(of: "\\bfast\\b", options: .regularExpression) == nil
    }

    /// Trim and bound a title so one runaway item can't dominate a chip row. Collapses inner
    /// whitespace runs to single spaces and caps the length at a chip-friendly size.
    static func boundTitle(_ raw: String, maxLength: Int = 28) -> String {
        let collapsed = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
        guard collapsed.count > maxLength else { return collapsed }
        return String(collapsed.prefix(maxLength)).trimmingCharacters(in: .whitespaces)
    }

    /// Map an SF Symbol name onto the allow-list: a known symbol passes through; anything
    /// unknown (an invented or typo'd name) becomes the neutral "checklist" glyph so the row
    /// never renders a blank box.
    static func validIcon(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return allowedIcons.contains(trimmed) ? trimmed : "checklist"
    }
}
