import Foundation
import SwiftData

/// A buddy's shareable, *low-stakes* daily state — just enough to feel each other's
/// presence ("they logged today, their little guy is thriving") without exposing
/// anything sensitive. **No weight, no calories, no numbers that invite comparison** —
/// only warm, encouraging signals. This is what gets published to / fetched from the
/// sync layer.
///
/// We persist the snapshot as a SwiftData @Model so the last-known buddy state survives
/// app restarts and is available offline (the UI can show "yesterday they were thriving"
/// even before the next sync). Stored as a single most-recent row per buddy.
///
/// Every property has a default value to stay SwiftData-migration- and CloudKit-ready
/// (see the note in `BuddyLink`).
@Model
final class BuddySnapshot {
    /// Who this snapshot belongs to (the buddy's user id). Lets us keep "my" published
    /// snapshot and "their" fetched snapshot straight if both are ever cached locally.
    var ownerUserID: String = ""

    /// Friendly name to show ("Bryan").
    var displayName: String = ""

    /// Current logging streak, in days. A gentle, motivating number — not a weight.
    var dayStreak: Int = 0

    /// Persisted as raw string (enum accessor below) for clean SwiftData + CloudKit
    /// round-tripping.
    var characterMoodRaw: String = BuddyCharacterMood.happy.rawValue

    /// Did they log anything today? Drives the "they showed up" presence dot.
    var loggedToday: Bool = false

    /// When they were last active, for a soft "active 2h ago" hint.
    var lastActive: Date = Date.now

    // MARK: Safe daily activity (for the playful, FAIR face-off)
    //
    // ONLY movement/hydration signals — steps, water, and a "moved today" flag — each
    // paired with that person's OWN goal so the face-off can be scored as a *percentage
    // of their own target*. That keeps it fair regardless of body or fitness (both people
    // can "win the day") and health-SAFE: there is **deliberately no weight and no
    // calorie data here**, and these goals are *floors to celebrate reaching*, never
    // ceilings (see `RESEARCH_social.md`). Every field defaults so the model stays
    // SwiftData-migration- and CloudKit-ready (older snapshots simply read as 0/false).

    /// Steps taken today (mirrors the dashboard's `StepsEntry` total).
    var stepsToday: Int = 0
    /// Their own daily step goal, so steps can be scored as % of *their* target.
    var stepGoal: Int = 0
    /// Fluid ounces of water logged today.
    var waterToday: Double = 0
    /// Their own daily water goal (oz), so water is scored as % of *their* target.
    var waterGoal: Double = 0
    /// Did they get any movement / a workout in today? A simple "showed up" flag —
    /// never a duration or intensity that invites comparison.
    var workedOutToday: Bool = false

    // MARK: Full shared data (OPT-IN — weight / calories / food)
    //
    // The fields above are the SAFE, activity-only face-off and are ALWAYS shared. The
    // fields below are the FULL daily picture — weight trend, calorie + protein progress,
    // and today's food names — and are ONLY meaningful when the owner has explicitly opted
    // in via `UserProfile.shareFullStatsWithBuddy` (mirrored here as `sharesFullData`).
    // This is an ADDITIVE channel for partners who chose to share everything; the
    // activity-only contract above is untouched. When `sharesFullData` is false these stay
    // at their 0/"" defaults and the display card renders nothing. Every field defaults so
    // the model stays SwiftData-migration- and CloudKit-ready (older snapshots read as
    // not-sharing with empty full data).

    /// Whether the owner opted in to sharing the full picture below. The display card only
    /// renders when this is `true`; otherwise the buddy sees just the activity face-off.
    var sharesFullData: Bool = false
    /// Their smoothed weight trend in lbs (NOT a raw scale reading — see `TrendCalculator`).
    var trendWeightLbs: Double = 0
    /// Their goal weight in lbs, for a soft "to goal X" hint.
    var goalWeightLbs: Double = 0
    /// Their weekly rate of change in lbs, SIGNED (negative = losing).
    var weeklyRateLbs: Double = 0
    /// Calories eaten so far today.
    var caloriesEaten: Double = 0
    /// Their daily calorie target (so calories read as progress, not a raw number).
    var calorieTarget: Double = 0
    /// Protein eaten so far today (g).
    var proteinEaten: Double = 0
    /// Their daily protein target (g).
    var proteinTarget: Double = 0
    /// Today's logged food names, comma-joined (already trimmed/limited at publish time).
    var todayFoods: String = ""

    init(ownerUserID: String,
         displayName: String,
         dayStreak: Int = 0,
         characterMood: BuddyCharacterMood = .happy,
         loggedToday: Bool = false,
         lastActive: Date = .now,
         stepsToday: Int = 0,
         stepGoal: Int = 0,
         waterToday: Double = 0,
         waterGoal: Double = 0,
         workedOutToday: Bool = false,
         sharesFullData: Bool = false,
         trendWeightLbs: Double = 0,
         goalWeightLbs: Double = 0,
         weeklyRateLbs: Double = 0,
         caloriesEaten: Double = 0,
         calorieTarget: Double = 0,
         proteinEaten: Double = 0,
         proteinTarget: Double = 0,
         todayFoods: String = "") {
        self.ownerUserID = ownerUserID
        self.displayName = displayName
        self.dayStreak = dayStreak
        self.characterMoodRaw = characterMood.rawValue
        self.loggedToday = loggedToday
        self.lastActive = lastActive
        self.stepsToday = stepsToday
        self.stepGoal = stepGoal
        self.waterToday = waterToday
        self.waterGoal = waterGoal
        self.workedOutToday = workedOutToday
        self.sharesFullData = sharesFullData
        self.trendWeightLbs = trendWeightLbs
        self.goalWeightLbs = goalWeightLbs
        self.weeklyRateLbs = weeklyRateLbs
        self.caloriesEaten = caloriesEaten
        self.calorieTarget = calorieTarget
        self.proteinEaten = proteinEaten
        self.proteinTarget = proteinTarget
        self.todayFoods = todayFoods
    }

    // MARK: Enum accessor
    var characterMood: BuddyCharacterMood {
        get { BuddyCharacterMood(rawValue: characterMoodRaw) ?? .happy }
        set { characterMoodRaw = newValue.rawValue }
    }
}

/// The mood of the buddy's shared little character, as seen from across the link.
///
/// Deliberately a small, self-contained, **String-backed** enum scoped to the Buddy
/// feature — NOT a reuse of `CompanionEngine.CompanionMood` (which is `Int`-backed and
/// lives in a file this work isn't allowed to touch). Keeping it independent means the
/// Buddy layer compiles in isolation and these raw values stay stable across the wire /
/// CloudKit regardless of any future changes to the local companion engine. The spec's
/// three shared moods map cleanly onto the companion's top tiers.
enum BuddyCharacterMood: String, Codable, CaseIterable, Identifiable {
    case thriving
    case happy
    case sleepy
    var id: String { rawValue }

    var label: String {
        switch self {
        case .thriving: return "Thriving"
        case .happy:    return "Happy"
        case .sleepy:   return "Sleepy"
        }
    }

    /// SF Symbol echoing the local companion's faces, for a consistent feel.
    var systemImage: String {
        switch self {
        case .thriving: return "face.smiling.inverse"
        case .happy:    return "face.smiling"
        case .sleepy:   return "moon.zzz.fill"
        }
    }
}
