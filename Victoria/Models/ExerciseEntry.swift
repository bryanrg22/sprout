import Foundation
import SwiftData

/// One machine / exercise done within a `WorkoutSession` — e.g. "Leg press · 135 lb · 3×10".
/// Linked to its session by `sessionID` (a flat foreign key; the app does NOT use SwiftData
/// `@Relationship` — see `BuddyLink` / `Nudge`). Strength-over-time (Phase 2) is just a query of
/// `ExerciseEntry` by `machineKey`, charting `weightLbs` over `WorkoutSession.date`.
///
/// Zero-friction defaults: tapping a machine logs a sensible **3 sets × 10 reps** with no weight
/// (`weightLbs == 0` means "unset") — reps, sets, and weight are all editable and all optional.
///
/// Every property has a default value so the model stays SwiftData-migration- and CloudKit-ready
/// (mirrors `ChecklistItem` / `BuddySnapshot`).
@Model
final class ExerciseEntry {
    var id: UUID = UUID()

    /// The owning `WorkoutSession.id`. Flat foreign key (no `@Relationship`).
    var sessionID: UUID = UUID()

    /// The owning session's `date`, **denormalized** onto each entry. Because the app uses flat
    /// foreign keys (no `@Relationship`), a `@Query` over `ExerciseEntry` can't sort by the parent
    /// session's date — so we copy it here on save. This is what powers "recents float to the top"
    /// (`@Query(sort: \.date, .reverse)` → `MachineCatalog.ranked`) and Phase 2's per-machine
    /// strength chart (query by `machineKey`, plot `weightLbs` over `date`) with no join.
    var date: Date = Date.now

    /// Stable catalog key (e.g. "leg_press"). For a custom "+ Add a machine" entry this is a
    /// generated key so it stays distinct in history without polluting the static catalog.
    var machineKey: String = ""

    /// Human-readable name shown in the grid / day detail ("Leg press").
    var displayName: String = ""

    /// SF Symbol (or asset) name for the tile. Custom entries default to `dumbbell.fill`.
    var iconName: String = "dumbbell.fill"

    /// Optional working weight in lbs. **0 = unset** (shown as "—"), so just tapping a machine
    /// records the 3×10 without forcing a number.
    var weightLbs: Double = 0

    /// Reps per set — defaults to the zero-friction 10.
    var reps: Int = 10

    /// Number of sets — defaults to the zero-friction 3.
    var sets: Int = 3

    init(id: UUID = UUID(),
         sessionID: UUID,
         date: Date = .now,
         machineKey: String = "",
         displayName: String = "",
         iconName: String = "dumbbell.fill",
         weightLbs: Double = 0,
         reps: Int = 10,
         sets: Int = 3) {
        self.id = id
        self.sessionID = sessionID
        self.date = date
        self.machineKey = machineKey
        self.displayName = displayName
        self.iconName = iconName
        self.weightLbs = weightLbs
        self.reps = reps
        self.sets = sets
    }
}
