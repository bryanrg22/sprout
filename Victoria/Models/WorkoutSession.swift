import Foundation
import SwiftData

/// A single logged workout session — the new, richer workout model behind the **Workouts**
/// tab. (The older `WorkoutEntry` powers the dashboard's "Today's checklist" movement log and
/// is left untouched.) A session captures *what kind* of workout it was, and for a gym session
/// *which muscle groups* it focused on; the individual machines/exercises live in separate
/// `ExerciseEntry` rows linked by `sessionID` — the app uses flat foreign-key IDs, not SwiftData
/// `@Relationship` (see `BuddyLink` / `Nudge`).
///
/// Every property has a default value so the model stays SwiftData-migration- and CloudKit-ready
/// (mirrors `ChecklistItem` / `BuddySnapshot`): older / partially-decoded rows simply read as the
/// sensible defaults below. Enums are stored as raw strings for clean CloudKit round-tripping.
@Model
final class WorkoutSession {
    var id: UUID = UUID()

    /// When the session happened. Stored as start-of-day **plus** the time it was logged, so the
    /// day is trivially comparable while the original time-of-day is preserved for ordering.
    var date: Date = Date.now

    /// The kind of workout (gym / run / walk / …), persisted as a raw string. See `kind`.
    var typeRaw: String = WorkoutKind.gym.rawValue

    /// Gym sessions only: the muscle groups trained, as a comma-joined list of `MuscleFocus`
    /// raw values (e.g. "chest,arms"). Empty for cardio / non-gym sessions. See `focuses`.
    var focusesRaw: String = ""

    /// Optional duration in minutes (0 = unset). The one field cardio sessions really need.
    var durationMinutes: Int = 0

    /// Free-text notes ("felt strong today"). Optional — defaults to empty.
    var notes: String = ""

    init(id: UUID = UUID(),
         date: Date = .now,
         kind: WorkoutKind = .gym,
         focuses: [MuscleFocus] = [],
         durationMinutes: Int = 0,
         notes: String = "") {
        self.id = id
        self.date = date
        self.typeRaw = kind.rawValue
        self.focusesRaw = MuscleFocus.join(focuses)
        self.durationMinutes = durationMinutes
        self.notes = notes
    }

    // MARK: Enum / set accessors

    /// The workout kind, bridged to/from the stored raw string.
    var kind: WorkoutKind {
        get { WorkoutKind(rawValue: typeRaw) ?? .other }
        set { typeRaw = newValue.rawValue }
    }

    /// The muscle-group focuses (gym only), bridged to/from the comma-joined raw string. Order is
    /// preserved on the way in; reads filter out anything unrecognized.
    var focuses: [MuscleFocus] {
        get { MuscleFocus.split(focusesRaw) }
        set { focusesRaw = MuscleFocus.join(newValue) }
    }
}
