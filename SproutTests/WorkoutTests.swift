import XCTest
@testable import Sprout

/// Pins the PURE pieces of the Phase-1 workout logger: the `MachineCatalog.ranked` "recent +
/// frequent first" ordering, the `MuscleFocus` comma-join round-trip, and the zero-friction
/// 3×10 defaults on `WorkoutSession` / `ExerciseEntry`. These are logic-only (no UI, no live
/// SwiftData store), so they run fast and deterministically.
final class WorkoutTests: XCTestCase {

    // Helper: a bare exercise row for a given machine key (other fields irrelevant to ranking).
    private func entry(_ key: String) -> ExerciseEntry {
        ExerciseEntry(sessionID: UUID(), machineKey: key, displayName: key, iconName: "dumbbell.fill")
    }

    // MARK: - MachineCatalog.ranked

    func testRankedWithNoHistoryIsCatalogOrder() {
        let ranked = MachineCatalog.ranked(history: [])
        XCTAssertEqual(ranked.map(\.key), MachineCatalog.all.map(\.key),
                       "Empty history must return the catalog untouched.")
    }

    func testRankedFloatsUsedMachinesToFront() {
        // "leg_press" lives deep in the catalog (Legs group); using it should float it to #1.
        let history = [entry("leg_press")]
        let ranked = MachineCatalog.ranked(history: history)
        XCTAssertEqual(ranked.first?.key, "leg_press",
                       "A used machine must rank ahead of every unused one.")
        // And nothing is lost — ranking reorders, never hides.
        XCTAssertEqual(ranked.count, MachineCatalog.all.count)
        XCTAssertEqual(Set(ranked.map(\.key)), Set(MachineCatalog.all.map(\.key)))
    }

    func testRankedMostFrequentFirst() {
        // Frequency is the primary signal ("most-popular first"): leg_press (used twice) must
        // outrank bicep_curl (used once), even though bicep_curl is the most-recent single entry.
        let history = [entry("bicep_curl"),   // most recent, but only once
                       entry("leg_press"),
                       entry("leg_press")]     // less recent, but more frequent
        let ranked = MachineCatalog.ranked(history: history)
        let leg   = ranked.firstIndex { $0.key == "leg_press" }!
        let bicep = ranked.firstIndex { $0.key == "bicep_curl" }!
        XCTAssertLessThan(leg, bicep, "More-frequently-used machine ranks first.")
        XCTAssertEqual(ranked.first?.key, "leg_press")
    }

    func testRankedRecencyBreaksFrequencyTies() {
        // Equal frecency (each used once, both in the same recency bucket) → the MORE-RECENT one
        // wins. Dates are explicit (not array order) so the tie is broken deterministically: with
        // ranking now date-driven (frecency), "lat_pulldown" used 1 day ago must rank ahead of
        // "seated_cable_row" used 2 days ago. (Detailed frecency cases live in MachineCatalogTests.)
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let history = [ExerciseEntry(sessionID: UUID(), date: now.addingTimeInterval(-1 * 86_400),
                                     machineKey: "lat_pulldown", displayName: "lat_pulldown", iconName: "dumbbell.fill"),
                       ExerciseEntry(sessionID: UUID(), date: now.addingTimeInterval(-2 * 86_400),
                                     machineKey: "seated_cable_row", displayName: "seated_cable_row", iconName: "dumbbell.fill")]
        let ranked = MachineCatalog.ranked(history: history, now: now)
        let pull = ranked.firstIndex { $0.key == "lat_pulldown" }!
        let row  = ranked.firstIndex { $0.key == "seated_cable_row" }!
        XCTAssertLessThan(pull, row, "Equal frecency: the most-recent machine ranks first.")
        XCTAssertEqual(ranked.first?.key, "lat_pulldown")
    }

    func testRankedIsStableForUnusedMachines() {
        // Unused machines must keep their original relative catalog order (no jitter).
        let history = [entry("leg_press")]
        let ranked = MachineCatalog.ranked(history: history)
        let unused = ranked.filter { $0.key != "leg_press" }.map(\.key)
        let catalogUnused = MachineCatalog.all.map(\.key).filter { $0 != "leg_press" }
        XCTAssertEqual(unused, catalogUnused, "Unused machines stay in catalog order.")
    }

    func testRankedIgnoresUnknownKeys() {
        // A custom/off-catalog key in history must not crash or inject a phantom machine.
        let history = [entry("custom_made_up_thing"), entry("leg_press")]
        let ranked = MachineCatalog.ranked(history: history)
        XCTAssertEqual(ranked.count, MachineCatalog.all.count)
        XCTAssertEqual(ranked.first?.key, "leg_press")
        XCTAssertFalse(ranked.contains { $0.key == "custom_made_up_thing" })
    }

    // MARK: - MuscleFocus comma-join round-trip

    func testFocusJoinRoundTrip() {
        let focuses: [MuscleFocus] = [.chest, .arms, .core]
        let raw = MuscleFocus.join(focuses)
        XCTAssertEqual(raw, "chest,arms,core")
        XCTAssertEqual(MuscleFocus.split(raw), focuses, "Join → split must be lossless + ordered.")
    }

    func testFocusSplitEmptyIsEmpty() {
        XCTAssertEqual(MuscleFocus.split(""), [])
        XCTAssertEqual(MuscleFocus.join([]), "")
    }

    func testFocusSplitDropsUnknownAndWhitespace() {
        // Tolerant of stray spaces and silently drops unknown tokens (forward-compat).
        XCTAssertEqual(MuscleFocus.split(" chest , bogus, legs "), [.chest, .legs])
    }

    func testSessionFocusesAccessorRoundTrips() {
        let session = WorkoutSession(kind: .gym, focuses: [.legs, .core])
        XCTAssertEqual(session.focusesRaw, "legs,core")
        XCTAssertEqual(session.focuses, [.legs, .core])
        // Setting via the accessor re-encodes the raw string.
        session.focuses = [.back]
        XCTAssertEqual(session.focusesRaw, "back")
    }

    // MARK: - 3×10 defaults + inits

    func testExerciseEntryDefaultsAre3x10NoWeight() {
        let e = ExerciseEntry(sessionID: UUID())
        XCTAssertEqual(e.sets, 3, "Default sets = 3.")
        XCTAssertEqual(e.reps, 10, "Default reps = 10.")
        XCTAssertEqual(e.weightLbs, 0, "Default weight unset (0).")
        XCTAssertEqual(e.iconName, "dumbbell.fill", "Default icon falls back to dumbbell.")
    }

    func testExercisePickDefaultsAre3x10() {
        let pick = ExercisePick(machineKey: "leg_press", displayName: "Leg press", iconName: "x")
        XCTAssertEqual(pick.sets, 3)
        XCTAssertEqual(pick.reps, 10)
        XCTAssertEqual(pick.weightLbs, 0)
    }

    func testWorkoutSessionInitStoresKindAndDefaults() {
        let s = WorkoutSession(kind: .run, durationMinutes: 30)
        XCTAssertEqual(s.kind, .run)
        XCTAssertEqual(s.typeRaw, "run")
        XCTAssertEqual(s.durationMinutes, 30)
        XCTAssertEqual(s.focusesRaw, "")
        XCTAssertEqual(s.notes, "")
    }

    func testWorkoutKindIsGymOnlyForGym() {
        XCTAssertTrue(WorkoutKind.gym.isGym)
        for k in WorkoutKind.allCases where k != .gym {
            XCTAssertFalse(k.isGym, "\(k.rawValue) should not be a gym kind.")
        }
    }

    func testExerciseEntryLinksToSession() {
        let session = WorkoutSession(kind: .gym, focuses: [.legs])
        let e = ExerciseEntry(sessionID: session.id, machineKey: "leg_press",
                              displayName: "Leg press", iconName: "x", weightLbs: 135)
        XCTAssertEqual(e.sessionID, session.id, "Flat foreign key points back at the session.")
        XCTAssertEqual(e.weightLbs, 135)
    }
}
