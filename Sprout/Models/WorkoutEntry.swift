import Foundation
import SwiftData

/// A logged workout / gym session. Kept deliberately simple — the goal is to reward
/// *showing up*, so even a 10-minute walk counts.
@Model
final class WorkoutEntry {
    var id: UUID = UUID()
    var date: Date = Date.now
    var typeRaw: String = WorkoutType.strength.rawValue
    var title: String = ""
    var durationMinutes: Int = 0
    /// Optional — most people don't know this; it's never required.
    var caloriesBurned: Double?
    /// Optional training split for strength days (push/pull/legs…), so patterns are visible.
    var focusRaw: String?
    var notes: String?
    var createdAt: Date = Date.now

    var type: WorkoutType {
        get { WorkoutType(rawValue: typeRaw) ?? .other }
        set { typeRaw = newValue.rawValue }
    }
    var focus: WorkoutFocus? {
        get { focusRaw.flatMap(WorkoutFocus.init(rawValue:)) }
        set { focusRaw = newValue?.rawValue }
    }

    init(date: Date = .now,
         type: WorkoutType = .strength,
         title: String = "",
         durationMinutes: Int = 0,
         caloriesBurned: Double? = nil,
         focus: WorkoutFocus? = nil,
         notes: String? = nil) {
        self.id = UUID()
        self.date = date
        self.typeRaw = type.rawValue
        self.title = title.isEmpty ? type.label : title
        self.durationMinutes = durationMinutes
        self.caloriesBurned = caloriesBurned
        self.focusRaw = focus?.rawValue
        self.notes = notes
        self.createdAt = .now
    }
}
