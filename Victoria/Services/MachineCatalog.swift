import Foundation

// MARK: - Workout kind

/// The *type* of a logged workout session. Distinct from `CoreEnums.WorkoutType` (which backs the
/// older dashboard `WorkoutEntry`): this is the body-of-work split the new Workouts tab asks for —
/// **gym / run / walk / cycle / swim / sport / yoga / other** — so it's deliberately its own enum
/// (a second `WorkoutType` would collide). Raw values are stable for CloudKit round-tripping.
enum WorkoutKind: String, Codable, CaseIterable, Identifiable {
    case gym, run, walk, cycle, swim, sport, yoga, other
    var id: String { rawValue }

    var label: String {
        switch self {
        case .gym:   return "Gym"
        case .run:   return "Run"
        case .walk:  return "Walk"
        case .cycle: return "Cycle"
        case .swim:  return "Swim"
        case .sport: return "Sport"
        case .yoga:  return "Yoga"
        case .other: return "Other"
        }
    }

    /// A real iOS-18 SF Symbol per kind.
    var systemImage: String {
        switch self {
        case .gym:   return "figure.strengthtraining.traditional"
        case .run:   return "figure.run"
        case .walk:  return "figure.walk"
        case .cycle: return "figure.outdoor.cycle"
        case .swim:  return "figure.pool.swim"
        case .sport: return "sportscourt.fill"
        case .yoga:  return "figure.yoga"
        case .other: return "figure.mixed.cardio"
        }
    }

    /// Only a gym session picks focuses + machines; every other kind is a simple duration log.
    var isGym: Bool { self == .gym }
}

// MARK: - Muscle focus

/// The muscle-group "focus" of a gym session (a body-part split — covers push/pull/legs too).
/// Multi-select and never required; focus only *reorders/highlights* the machine grid, it never
/// hides machines. Persisted on `WorkoutSession` as a comma-joined list of these raw values.
enum MuscleFocus: String, Codable, CaseIterable, Identifiable {
    case chest, back, shoulders, arms, legs, core, other
    var id: String { rawValue }

    var label: String {
        switch self {
        case .chest:     return "Chest"
        case .back:      return "Back"
        case .shoulders: return "Shoulders"
        case .arms:      return "Arms"
        case .legs:      return "Legs"
        case .core:      return "Core"
        case .other:     return "Other"
        }
    }

    /// A real iOS-18 SF Symbol per focus, for the focus chips.
    var systemImage: String {
        switch self {
        case .chest:     return "figure.arms.open"
        case .back:      return "figure.strengthtraining.traditional"
        case .shoulders: return "figure.cooldown"
        case .arms:      return "dumbbell.fill"
        case .legs:      return "figure.strengthtraining.functional"
        case .core:      return "figure.core.training"
        case .other:     return "ellipsis.circle.fill"
        }
    }

    // MARK: Comma-join round-trip (used by `WorkoutSession.focusesRaw`)

    /// Join focuses into the stored "chest,arms" form (order preserved, raw values).
    static func join(_ focuses: [MuscleFocus]) -> String {
        focuses.map(\.rawValue).joined(separator: ",")
    }

    /// Parse a stored "chest,arms" string back into focuses, dropping anything unrecognized /
    /// empty. Tolerant of stray whitespace so hand-edited / migrated data still reads cleanly.
    static func split(_ raw: String) -> [MuscleFocus] {
        raw.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .compactMap { MuscleFocus(rawValue: $0) }
    }
}

// MARK: - Machine

/// One catalog entry: a gym machine / exercise (or a piece of cardio equipment). `key` is the
/// stable id stored on `ExerciseEntry.machineKey`; `focus` ties it to a muscle group so the grid
/// can highlight + float matches to the top when that focus is selected.
struct Machine: Identifiable, Hashable {
    let key: String
    let name: String
    let icon: String          // SF Symbol
    let focus: MuscleFocus
    let isCardio: Bool

    var id: String { key }

    init(key: String, name: String, icon: String, focus: MuscleFocus, isCardio: Bool = false) {
        self.key = key
        self.name = name
        self.icon = icon
        self.focus = focus
        self.isCardio = isCardio
    }
}

// MARK: - Catalog

/// The curated, in-code machine catalog (Phase 1) — the web-researched seed list from
/// `docs/workout-redesign.md`. "Other" + the describe-to-Vita flow (Phase 3) covers anything
/// missing. The log grid shows YOUR recents/most-used first, then this curated order.
///
/// SF Symbols throughout (Phase 1 decision). Where Apple has no machine-specific glyph we use a
/// sensible figure/equipment symbol, falling back to `dumbbell.fill`.
enum MachineCatalog {

    // A few shared, real SF Symbols reused across entries for consistency.
    private static let strength = "figure.strengthtraining.traditional"
    private static let functional = "figure.strengthtraining.functional"
    private static let dumbbell = "dumbbell.fill"

    /// The full curated list, grouped by focus in catalog order (Chest → Back → Shoulders →
    /// Arms → Legs → Core → Cardio). This order is the tiebreak after the user's own history.
    static let all: [Machine] = [
        // Chest — ordered most-popular first within the focus (web-researched: chest press &
        // bench press are the staples, pec deck the classic isolation). Personal recents still
        // float above this via `ranked(history:)`.
        Machine(key: "chest_press",        name: "Chest press",        icon: strength,   focus: .chest),
        Machine(key: "bench_press",        name: "Bench press",        icon: "dumbbell.fill", focus: .chest),
        Machine(key: "pec_deck",           name: "Pec deck",           icon: "figure.arms.open", focus: .chest),
        Machine(key: "incline_chest_press",name: "Incline chest press",icon: strength,   focus: .chest),
        Machine(key: "cable_crossover",    name: "Cable crossover",    icon: "figure.arms.open", focus: .chest),
        Machine(key: "push_up",            name: "Push-up",            icon: "figure.core.training", focus: .chest),

        // Back — lat pulldown & seated row are the most-used; deadlift is a staple pull.
        Machine(key: "lat_pulldown",       name: "Lat pulldown",       icon: strength,   focus: .back),
        Machine(key: "seated_cable_row",   name: "Seated cable row",   icon: strength,   focus: .back),
        Machine(key: "t_bar_row",          name: "T-bar row",          icon: "dumbbell.fill", focus: .back),
        Machine(key: "deadlift",           name: "Deadlift",           icon: "dumbbell.fill", focus: .back),
        Machine(key: "assisted_pull_up",   name: "Assisted pull-up",   icon: functional, focus: .back),
        Machine(key: "back_extension",     name: "Back extension",     icon: "figure.core.training", focus: .back),

        // Shoulders — press first, then the lateral/overhead staples, rear delt last.
        Machine(key: "shoulder_press",     name: "Shoulder press",     icon: strength,   focus: .shoulders),
        Machine(key: "lateral_raise",      name: "Lateral raise",      icon: "dumbbell.fill", focus: .shoulders),
        Machine(key: "overhead_press",     name: "Overhead press",     icon: "dumbbell.fill", focus: .shoulders),
        Machine(key: "reverse_pec_deck",   name: "Reverse pec deck",   icon: "figure.arms.open", focus: .shoulders),
        Machine(key: "cable_lateral_raise",name: "Cable lateral raise",icon: "dumbbell.fill", focus: .shoulders),

        // Arms — the curl + pushdown staples first.
        Machine(key: "bicep_curl",         name: "Bicep curl",         icon: "dumbbell.fill", focus: .arms),
        Machine(key: "tricep_pushdown",    name: "Tricep pushdown",    icon: strength,   focus: .arms),
        Machine(key: "cable_curl",         name: "Cable curl",         icon: "dumbbell.fill", focus: .arms),
        Machine(key: "preacher_curl",      name: "Preacher curl",      icon: "dumbbell.fill", focus: .arms),
        Machine(key: "assisted_dip",       name: "Assisted dip",       icon: functional, focus: .arms),
        Machine(key: "skullcrusher",       name: "Skullcrusher",       icon: "dumbbell.fill", focus: .arms),

        // Legs — leg press is THE staple; squat rack & extension/curl next.
        Machine(key: "leg_press",          name: "Leg press",          icon: strength,   focus: .legs),
        Machine(key: "squat_rack",         name: "Squat rack",         icon: functional, focus: .legs),
        Machine(key: "leg_extension",      name: "Leg extension",      icon: strength,   focus: .legs),
        Machine(key: "leg_curl",           name: "Leg curl",           icon: strength,   focus: .legs),
        Machine(key: "hack_squat",         name: "Hack squat",         icon: functional, focus: .legs),
        Machine(key: "calf_raise",         name: "Calf raise",         icon: "figure.strengthtraining.functional", focus: .legs),
        Machine(key: "smith_machine",      name: "Smith machine",      icon: functional, focus: .legs),
        Machine(key: "hip_thrust",         name: "Hip thrust",         icon: functional, focus: .legs),
        Machine(key: "hip_abductor",       name: "Hip abductor",       icon: strength,   focus: .legs),
        Machine(key: "hip_adductor",       name: "Hip adductor",       icon: strength,   focus: .legs),

        // Core
        Machine(key: "ab_crunch_machine",  name: "Ab crunch machine",  icon: "figure.core.training", focus: .core),
        Machine(key: "cable_crunch",       name: "Cable crunch",       icon: "figure.core.training", focus: .core),
        Machine(key: "captains_chair",     name: "Captain's chair",    icon: "figure.core.training", focus: .core),
        Machine(key: "roman_chair",        name: "Roman chair",        icon: "figure.core.training", focus: .core),

        // Cardio (shown for run / other kinds, and tagged isCardio)
        Machine(key: "treadmill",          name: "Treadmill",          icon: "figure.run",            focus: .legs, isCardio: true),
        Machine(key: "bike",               name: "Bike",               icon: "figure.indoor.cycle",   focus: .legs, isCardio: true),
        Machine(key: "elliptical",         name: "Elliptical",         icon: "figure.elliptical",     focus: .legs, isCardio: true),
        Machine(key: "rower",              name: "Rower",              icon: "figure.indoor.rowing",  focus: .back, isCardio: true),
        Machine(key: "stairmaster",        name: "Stairmaster",        icon: "figure.stair.stepper",  focus: .legs, isCardio: true),
    ]

    /// Fast key → machine lookup (e.g. to resolve a stored `ExerciseEntry.machineKey`).
    static let byKey: [String: Machine] = Dictionary(uniqueKeysWithValues: all.map { ($0.key, $0) })

    static func machine(for key: String) -> Machine? { byKey[key] }

    /// "Popular / recent first": rank the catalog by the user's own history so the machines she
    /// actually uses float to the top, with everything else keeping catalog order behind them.
    ///
    /// Ranking key, in order:
    ///  1. **Used before any unused** — anything in `history` outranks anything that isn't.
    ///  2. **Most-frequent first** — a machine used more often ranks higher ("most-popular").
    ///  3. **Most-recent breaks ties** — equal frequency → the one used more recently wins.
    ///  4. **Catalog order is the final, stable tiebreak** — so the grid never jitters.
    ///
    /// `history` is expected newest-first (the `@Query(order: .reverse)` order); recency is taken
    /// from first-appearance index, so a newest-first list reads correctly.
    static func ranked(history: [ExerciseEntry]) -> [Machine] {
        guard !history.isEmpty else { return all }

        var frequency: [String: Int] = [:]
        // Recency rank: 0 = most-recent appearance (smaller index = more recent, since the list
        // is newest-first). `nil` for unused machines.
        var firstSeenIndex: [String: Int] = [:]
        for (i, entry) in history.enumerated() {
            frequency[entry.machineKey, default: 0] += 1
            if firstSeenIndex[entry.machineKey] == nil { firstSeenIndex[entry.machineKey] = i }
        }

        // Stable index for the final tiebreak.
        let catalogIndex = Dictionary(uniqueKeysWithValues: all.enumerated().map { ($0.element.key, $0.offset) })

        return all.sorted { lhs, rhs in
            let lUsed = frequency[lhs.key] != nil
            let rUsed = frequency[rhs.key] != nil
            // 1. Used machines come first.
            if lUsed != rUsed { return lUsed }

            if lUsed && rUsed {
                // 2. Most-frequent first.
                let lf = frequency[lhs.key] ?? 0, rf = frequency[rhs.key] ?? 0
                if lf != rf { return lf > rf }
                // 3. Then most-recent (smaller firstSeenIndex) first.
                let lr = firstSeenIndex[lhs.key] ?? Int.max, rr = firstSeenIndex[rhs.key] ?? Int.max
                if lr != rr { return lr < rr }
            }
            // 4. Stable: keep catalog order.
            return (catalogIndex[lhs.key] ?? 0) < (catalogIndex[rhs.key] ?? 0)
        }
    }
}
