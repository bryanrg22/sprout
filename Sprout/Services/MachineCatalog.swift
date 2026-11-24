import Foundation
import SwiftUI
import UIKit

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

// MARK: - Home gym

/// The user's primary gym. Stored on `UserProfile` (as `homeGymRaw`) and shown in Settings; used
/// for photo/context personalization only. **It does NOT filter the machine list** — the catalog
/// stays universal (per-gym machine subsets are a later phase). Raw values are stable for CloudKit.
enum HomeGym: String, Codable, CaseIterable, Identifiable {
    case usc, twentyFourHour
    var id: String { rawValue }

    var label: String {
        switch self {
        case .usc:           return "USC Recreation"
        case .twentyFourHour: return "24 Hour Fitness"
        }
    }

    /// A one-line equipment hint shown under the label.
    var subtitle: String {
        switch self {
        case .usc:           return "Hammer Strength · Lyon + Village"
        case .twentyFourHour: return "Hoist ROC-IT machines"
        }
    }
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

// MARK: - Exercise form

/// How a move is performed / what it uses — this drives the tile ICON. A muscle can be trained
/// several ways (a bicep curl is "bicep work" with dumbbells, a cable, or a machine), so the
/// catalog lists the variations and the icon signals the form at a glance:
///   • `.machine` / `.cardio` → a real product PHOTO (`machine_<key>`)
///   • `.barbell`/`.dumbbell`/`.cable`/`.bodyweight` → a shared PICTOGRAM (`form_<form>`), unless the
///     move has its own bundled pictogram (e.g. `machine_push_up`, `machine_deadlift`).
enum ExerciseForm: String, Codable {
    case machine, barbell, dumbbell, cable, bodyweight, cardio

    /// The shared pictogram asset for a free-weight form, or nil to fall back to a photo / SF Symbol.
    var pictogramAsset: String? {
        switch self {
        case .barbell:    return "form_barbell"
        case .dumbbell:   return "form_dumbbell"
        case .cable:      return "form_cable"
        // Bodyweight is too varied for one glyph — a pull-up, a crunch and a squat share nothing —
        // so it has NO shared pictogram. A bodyweight move either ships its own `machine_<key>`
        // pictogram (push-up, plank) or falls back to its SF Symbol. (`form_bodyweight` is unused.)
        case .bodyweight: return nil
        case .machine, .cardio: return nil
        }
    }
}

// MARK: - Machine

/// One catalog entry: a gym machine / exercise (or a piece of cardio equipment). `key` is the
/// stable id stored on `ExerciseEntry.machineKey`; `focus` ties it to a muscle group so the grid
/// can highlight + float matches to the top when that focus is selected. `form` drives the icon.
struct Machine: Identifiable, Hashable {
    let key: String
    let name: String
    let icon: String          // SF Symbol fallback
    let focus: MuscleFocus
    let isCardio: Bool
    let form: ExerciseForm

    var id: String { key }

    init(key: String, name: String, icon: String, focus: MuscleFocus,
         isCardio: Bool = false, form: ExerciseForm = .machine) {
        self.key = key
        self.name = name
        self.icon = icon
        self.focus = focus
        self.isCardio = isCardio
        self.form = form
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
    private static let core = "figure.core.training"

    /// The full curated list, grouped by focus in catalog order (Chest → Back → Shoulders →
    /// Arms → Legs → Core → Cardio). This order is the tiebreak after the user's own history.
    static let all: [Machine] = [
        // CHEST — machine staples first (chest/bench press, pec deck), then the dumbbell, incline
        // and bodyweight variations. The form drives the icon: machine → photo, free-weight → a
        // shared pictogram. Personal recents still float above all of this via `ranked(history:)`.
        Machine(key: "chest_press",           name: "Chest press",            icon: strength,           focus: .chest),
        Machine(key: "bench_press",           name: "Bench press",            icon: dumbbell,           focus: .chest, form: .barbell),
        Machine(key: "db_bench_press",        name: "Dumbbell press",         icon: dumbbell,           focus: .chest, form: .dumbbell),
        Machine(key: "incline_chest_press",   name: "Incline chest press",    icon: strength,           focus: .chest),
        Machine(key: "incline_db_press",      name: "Incline dumbbell press", icon: dumbbell,           focus: .chest, form: .dumbbell),
        Machine(key: "incline_barbell_press", name: "Incline barbell press",  icon: dumbbell,           focus: .chest, form: .barbell),
        Machine(key: "pec_deck",              name: "Pec deck",               icon: "figure.arms.open", focus: .chest),
        Machine(key: "cable_crossover",       name: "Cable crossover",        icon: "figure.arms.open", focus: .chest, form: .cable),
        Machine(key: "push_up",               name: "Push-up",                icon: functional,         focus: .chest, form: .bodyweight),
        Machine(key: "chest_dip",             name: "Chest dip",              icon: functional,         focus: .chest, form: .bodyweight),

        // BACK — lat pulldown & rows are the most-used; deadlift is the staple pull.
        Machine(key: "lat_pulldown",          name: "Lat pulldown",           icon: strength,           focus: .back),
        Machine(key: "pull_up",               name: "Pull-up",                icon: functional,         focus: .back, form: .bodyweight),
        Machine(key: "seated_cable_row",      name: "Seated cable row",       icon: strength,           focus: .back, form: .cable),
        Machine(key: "barbell_row",           name: "Barbell row",            icon: dumbbell,           focus: .back, form: .barbell),
        Machine(key: "db_row",                name: "Dumbbell row",           icon: dumbbell,           focus: .back, form: .dumbbell),
        Machine(key: "t_bar_row",             name: "T-bar row",              icon: dumbbell,           focus: .back, form: .barbell),
        Machine(key: "chest_supported_row",   name: "Chest-supported row",    icon: dumbbell,           focus: .back, form: .dumbbell),
        Machine(key: "straight_arm_pulldown", name: "Straight-arm pulldown",  icon: strength,           focus: .back, form: .cable),
        Machine(key: "deadlift",              name: "Deadlift",               icon: dumbbell,           focus: .back, form: .barbell),
        Machine(key: "assisted_pull_up",      name: "Assisted pull-up",       icon: functional,         focus: .back),
        Machine(key: "back_extension",        name: "Back extension",         icon: core,               focus: .back, form: .bodyweight),
        Machine(key: "shrug",                 name: "Shrug",                  icon: dumbbell,           focus: .back, form: .dumbbell),

        // SHOULDERS — press first, then the lateral / front / rear-delt raises.
        Machine(key: "shoulder_press",        name: "Shoulder press",         icon: strength,           focus: .shoulders),
        Machine(key: "db_shoulder_press",     name: "Dumbbell shoulder press",icon: dumbbell,           focus: .shoulders, form: .dumbbell),
        Machine(key: "overhead_press",        name: "Overhead press",         icon: dumbbell,           focus: .shoulders, form: .barbell),
        Machine(key: "arnold_press",          name: "Arnold press",           icon: dumbbell,           focus: .shoulders, form: .dumbbell),
        Machine(key: "lateral_raise",         name: "Lateral raise",          icon: dumbbell,           focus: .shoulders),
        Machine(key: "db_lateral_raise",      name: "Dumbbell lateral raise", icon: dumbbell,           focus: .shoulders, form: .dumbbell),
        Machine(key: "cable_lateral_raise",   name: "Cable lateral raise",    icon: dumbbell,           focus: .shoulders, form: .cable),
        Machine(key: "front_raise",           name: "Front raise",            icon: dumbbell,           focus: .shoulders, form: .dumbbell),
        Machine(key: "reverse_pec_deck",      name: "Reverse pec deck",       icon: "figure.arms.open", focus: .shoulders),
        Machine(key: "rear_delt_fly",         name: "Rear delt fly",          icon: dumbbell,           focus: .shoulders, form: .dumbbell),
        Machine(key: "face_pull",             name: "Face pull",              icon: strength,           focus: .shoulders, form: .cable),
        Machine(key: "upright_row",           name: "Upright row",            icon: dumbbell,           focus: .shoulders, form: .barbell),

        // ARMS — biceps (machine / dumbbell / barbell / cable curls), then triceps.
        Machine(key: "bicep_curl",            name: "Bicep curl",             icon: dumbbell,           focus: .arms),
        Machine(key: "db_curl",               name: "Dumbbell curl",          icon: dumbbell,           focus: .arms, form: .dumbbell),
        Machine(key: "barbell_curl",          name: "Barbell curl",           icon: dumbbell,           focus: .arms, form: .barbell),
        Machine(key: "hammer_curl",           name: "Hammer curl",            icon: dumbbell,           focus: .arms, form: .dumbbell),
        Machine(key: "cable_curl",            name: "Cable curl",             icon: dumbbell,           focus: .arms, form: .cable),
        Machine(key: "preacher_curl",         name: "Preacher curl",          icon: dumbbell,           focus: .arms),
        Machine(key: "tricep_pushdown",       name: "Tricep pushdown",        icon: strength,           focus: .arms, form: .cable),
        Machine(key: "overhead_tricep_extension", name: "Overhead extension", icon: dumbbell,           focus: .arms, form: .dumbbell),
        Machine(key: "close_grip_bench",      name: "Close-grip bench",       icon: dumbbell,           focus: .arms, form: .barbell),
        Machine(key: "skullcrusher",          name: "Skullcrusher",           icon: dumbbell,           focus: .arms, form: .barbell),
        Machine(key: "tricep_kickback",       name: "Tricep kickback",        icon: dumbbell,           focus: .arms, form: .dumbbell),
        Machine(key: "assisted_dip",          name: "Assisted dip",           icon: functional,         focus: .arms),

        // LEGS — leg press is THE staple; squats, the posterior-chain & accessory work follow.
        Machine(key: "leg_press",             name: "Leg press",              icon: strength,           focus: .legs),
        Machine(key: "squat_rack",            name: "Squat rack",             icon: functional,         focus: .legs, form: .barbell),
        Machine(key: "front_squat",           name: "Front squat",            icon: dumbbell,           focus: .legs, form: .barbell),
        Machine(key: "goblet_squat",          name: "Goblet squat",           icon: dumbbell,           focus: .legs, form: .dumbbell),
        Machine(key: "hack_squat",            name: "Hack squat",             icon: functional,         focus: .legs),
        Machine(key: "leg_extension",         name: "Leg extension",          icon: strength,           focus: .legs),
        Machine(key: "leg_curl",              name: "Leg curl",               icon: strength,           focus: .legs),
        Machine(key: "romanian_deadlift",     name: "Romanian deadlift",      icon: dumbbell,           focus: .legs, form: .barbell),
        Machine(key: "lunge",                 name: "Lunge",                  icon: dumbbell,           focus: .legs, form: .dumbbell),
        Machine(key: "bulgarian_split_squat", name: "Bulgarian split squat",  icon: dumbbell,           focus: .legs, form: .dumbbell),
        Machine(key: "step_up",               name: "Step-up",                icon: dumbbell,           focus: .legs, form: .dumbbell),
        Machine(key: "smith_machine",         name: "Smith machine",          icon: functional,         focus: .legs),
        Machine(key: "hip_thrust",            name: "Hip thrust",             icon: functional,         focus: .legs, form: .barbell),
        Machine(key: "hip_abductor",          name: "Hip abductor",           icon: strength,           focus: .legs),
        Machine(key: "hip_adductor",          name: "Hip adductor",           icon: strength,           focus: .legs),
        Machine(key: "calf_raise",            name: "Calf raise",             icon: functional,         focus: .legs),

        // CORE — the machine stations, then the bodyweight ab work.
        Machine(key: "ab_crunch_machine",     name: "Ab crunch machine",      icon: core,               focus: .core),
        Machine(key: "crunch",                name: "Crunch",                 icon: core,               focus: .core, form: .bodyweight),
        Machine(key: "cable_crunch",          name: "Cable crunch",           icon: core,               focus: .core, form: .cable),
        Machine(key: "captains_chair",        name: "Captain's chair",        icon: core,               focus: .core),
        Machine(key: "hanging_knee_raise",    name: "Hanging knee raise",     icon: core,               focus: .core, form: .bodyweight),
        Machine(key: "roman_chair",           name: "Roman chair",            icon: core,               focus: .core),
        Machine(key: "plank",                 name: "Plank",                  icon: core,               focus: .core, form: .bodyweight),
        Machine(key: "russian_twist",         name: "Russian twist",          icon: core,               focus: .core, form: .bodyweight),

        // CARDIO (shown for run / other kinds, and tagged isCardio).
        Machine(key: "treadmill",             name: "Treadmill",              icon: "figure.run",            focus: .legs, isCardio: true, form: .cardio),
        Machine(key: "bike",                  name: "Bike",                   icon: "figure.indoor.cycle",   focus: .legs, isCardio: true, form: .cardio),
        Machine(key: "elliptical",            name: "Elliptical",             icon: "figure.elliptical",     focus: .legs, isCardio: true, form: .cardio),
        Machine(key: "rower",                 name: "Rower",                  icon: "figure.indoor.rowing",  focus: .back, isCardio: true, form: .cardio),
        Machine(key: "stairmaster",           name: "Stairmaster",            icon: "figure.stair.stepper",  focus: .legs, isCardio: true, form: .cardio),
    ]

    /// Fast key → machine lookup (e.g. to resolve a stored `ExerciseEntry.machineKey`).
    static let byKey: [String: Machine] = Dictionary(uniqueKeysWithValues: all.map { ($0.key, $0) })

    /// key → position in `all`, for the stable catalog-order tiebreak (ranking) and for sorting a
    /// session's logged exercises into a tidy, intentional order on the detail page.
    static let catalogIndex: [String: Int] = Dictionary(
        uniqueKeysWithValues: all.enumerated().map { ($0.element.key, $0.offset) })

    static func machine(for key: String) -> Machine? { byKey[key] }

    /// "Go-to lifts first": rank the catalog by the user's own history so the machines she actually
    /// reaches for float to the top, with everything else keeping catalog order behind them.
    ///
    /// Scoring is **frecency** (Mozilla's frequency-+-recency model, as used for awesomebar URL
    /// ranking): every logged use contributes a weight that *decays* with how long ago it was, and a
    /// machine's score is the SUM of those weights. So a fresh streak dominates and "sticks" for
    /// weeks (5 bicep curls this week beat 8 from three months ago), while stale usage fades on its
    /// own — exactly the "my current go-to pins to the top, and doesn't get switched out from under
    /// me" behavior, without ever fully forgetting an old favorite.
    ///
    /// Recency buckets (by whole calendar days ago, `Calendar.current`):
    ///   • ≤ 2 days → 8   • ≤ 7 days → 4   • ≤ 30 days → 2   • else → 1
    ///
    /// Sort key, in order:
    ///  1. **Used before any unused** — anything in `history` outranks anything that isn't.
    ///  2. **Higher frecency first** — the current go-to (recent + frequent) outranks the rest.
    ///  3. **Most-recent breaks ties** — equal frecency → the one used more recently wins.
    ///  4. **Catalog order is the final, stable tiebreak** — so the grid never jitters. This is also
    ///     the *popularity prior*: it's "most-popular-first" within each focus, so before she has any
    ///     history (and for moves she's never tried), the grid already leads with the popular picks.
    ///
    /// `now` is injectable so the recency math is deterministic in tests (defaults to wall-clock, so
    /// the existing `ranked(history:)` call site keeps compiling unchanged). `history` order doesn't
    /// matter — scoring reads each entry's `date`, not its position.
    static func ranked(history: [ExerciseEntry], now: Date = .now) -> [Machine] {
        guard !history.isEmpty else { return all }

        let cal = Calendar.current
        let today = cal.startOfDay(for: now)

        var frecency: [String: Int] = [:]
        // Tiebreak signal: the single most-recent use of each machine. `nil` for unused machines.
        var mostRecent: [String: Date] = [:]
        for entry in history {
            // Whole calendar days between the use and today; future-dated rows clamp to 0 (today).
            let entryDay = cal.startOfDay(for: entry.date)
            let daysAgo = max(0, cal.dateComponents([.day], from: entryDay, to: today).day ?? 0)
            frecency[entry.machineKey, default: 0] += weight(daysAgo: daysAgo)
            if let seen = mostRecent[entry.machineKey] {
                if entry.date > seen { mostRecent[entry.machineKey] = entry.date }
            } else {
                mostRecent[entry.machineKey] = entry.date
            }
        }

        // `catalogIndex` (static) is the stable final tiebreak / popularity prior.
        return all.sorted { lhs, rhs in
            let lUsed = frecency[lhs.key] != nil
            let rUsed = frecency[rhs.key] != nil
            // 1. Used machines come first.
            if lUsed != rUsed { return lUsed }

            if lUsed && rUsed {
                // 2. Higher frecency first.
                let lf = frecency[lhs.key] ?? 0, rf = frecency[rhs.key] ?? 0
                if lf != rf { return lf > rf }
                // 3. Then more-recent first.
                let lr = mostRecent[lhs.key] ?? .distantPast, rr = mostRecent[rhs.key] ?? .distantPast
                if lr != rr { return lr > rr }
            }
            // 4. Stable: keep catalog order.
            return (catalogIndex[lhs.key] ?? 0) < (catalogIndex[rhs.key] ?? 0)
        }
    }

    /// The frecency weight for a single use that happened `daysAgo` whole calendar days ago — the
    /// recency decay buckets (Mozilla-style). A machine's frecency is the SUM of these across its
    /// uses, so both *how recent* and *how often* feed the score.
    private static func weight(daysAgo: Int) -> Int {
        switch daysAgo {
        case ..<0:  return 8   // defensive: callers clamp negatives, but treat future as "today".
        case 0...2: return 8
        case 3...7: return 4
        case 8...30: return 2
        default:    return 1
        }
    }

    /// The asset-image name a machine photo is looked up under, for a given catalog `key` /
    /// `ExerciseEntry.machineKey`: e.g. `leg_press` → `machine_leg_press`. Keep bundled assets
    /// named to match (lowercase, underscore — identical to the catalog key).
    static func photoAssetName(for key: String) -> String { "machine_\(key)" }

    /// Keys whose bundled `machine_<key>` asset is a flat exercise PICTOGRAM (a hand-sourced
    /// silhouette for moves with no machine to photograph), not a product photo. `MachineImage`
    /// scales these down so their solid ink doesn't outweigh the detailed machine shots.
    static let pictogramKeys: Set<String> = ["push_up", "deadlift", "skullcrusher", "cable_curl", "plank"]
}

// MARK: - Machine image (photo with SF-Symbol fallback)

/// Renders a machine's real bundled photo when one exists, gracefully falling back to its SF
/// Symbol otherwise. Photos are asset images named `machine_<key>` (see
/// `MachineCatalog.photoAssetName`) keyed by `Machine.key` / `ExerciseEntry.machineKey`; until an
/// asset is added the symbol shows, so this is safe for every machine today.
///
/// The view fills whatever frame the call site gives it (it has no intrinsic size of its own),
/// so existing tile/disc framing + symbol styling is preserved as the fallback.
struct MachineImage: View {
    /// `Machine.key` / `ExerciseEntry.machineKey` — drives the `machine_<key>` asset lookup.
    let key: String
    /// The SF Symbol to fall back to (`Machine.icon` / `ExerciseEntry.iconName`).
    let symbolName: String

    @Environment(\.colorScheme) private var colorScheme

    /// This key's catalog form, which drives the shared-pictogram fallback. Off-catalog / custom
    /// keys have no catalog entry → `.machine` (so they render a photo if one happens to exist,
    /// else the SF Symbol — never a free-weight pictogram).
    private var form: ExerciseForm { MachineCatalog.machine(for: key)?.form ?? .machine }

    /// The artwork to draw, resolved in priority order, plus whether it's a flat PICTOGRAM (scaled
    /// down so its solid ink doesn't outweigh the airy product photos beside it):
    ///   1. a bundled `machine_<key>` — a product PHOTO, unless it's a hand-drawn pictogram
    ///      (`pictogramKeys`: push-up, plank, deadlift, skullcrusher, cable curl);
    ///   2. else the shared `form_<form>` pictogram for a free-weight move (dumbbell / barbell / cable);
    ///   3. else `nil` → the SF-Symbol fallback (`symbolName`).
    private var artwork: (name: String, isPictogram: Bool)? {
        let photoName = MachineCatalog.photoAssetName(for: key)
        if UIImage(named: photoName) != nil {
            return (photoName, MachineCatalog.pictogramKeys.contains(key))
        }
        if let shared = form.pictogramAsset, UIImage(named: shared) != nil {
            return (shared, true)
        }
        return nil
    }

    var body: some View {
        if let artwork {
            let image = Image(artwork.name).resizable().scaledToFit()
                .scaleEffect(artwork.isPictogram ? 0.58 : 1)
            // The cut-outs / ink are dark — invisible on the near-black dark-theme tiles. Flip their
            // luminance so they render LIGHT (still transparent, no white box). The art is greyscale,
            // so this reads as a natural light/chrome machine or a clean light pictogram.
            if colorScheme == .dark {
                image.colorInvert()
            } else {
                image
            }
        } else {
            Image(systemName: symbolName)
        }
    }
}
