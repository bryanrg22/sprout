import Foundation
import HealthKit
import SwiftData

/// Sleep + auto-detected-workout ingestion from Apple Health — the SECOND pipe for
/// tracker data (the primary is the direct Google Health API in `GoogleHealth/`,
/// which needs no bridge app). Anything that lands in Apple Health — an Apple Watch,
/// a bridge app, another tracker — gets mirrored as SPARSE DAILY AGGREGATES here,
/// exactly like `HealthKitSteps`:
///
///   - one `SleepEntry` per night (asleep + in-bed minutes)
///   - one `DetectedWorkout` per HKWorkout (activity, duration, kcal), deduped by UUID
///
/// Deliberately NOT raw streams (per-minute heart rate etc.) — the coach needs "slept
/// 7h 20m, ran 32 min", and daily aggregates keep the prompt, storage, and privacy
/// footprint small. All reads no-op gracefully without authorization.
extension HealthKitService {

    // MARK: - Sleep

    /// One night's aggregated sleep — totals PLUS the stage breakdown a stage-capable
    /// tracker (Fitbit Air etc.) reports. Stages stay 0 for totals-only sources.
    struct NightSleep: Sendable, Equatable {
        var asleep = 0
        var inBed = 0
        var deep = 0
        var rem = 0
        var core = 0
        var awake = 0
    }

    /// Per-night sleep for the last `days` days, keyed by the START-OF-DAY OF THE
    /// WAKE MORNING (a night that ends at 7am Tuesday belongs to Tuesday). When several
    /// sources report the same night (e.g. Fitbit via a bridge AND Apple Watch), the
    /// single source with the MOST asleep minutes wins — summing across sources would
    /// double-count the same night.
    func dailySleep(days: Int) async -> [Date: NightSleep] {
        guard Self.isAvailable,
              let sleepType = HKCategoryType.categoryType(forIdentifier: .sleepAnalysis) else { return [:] }
        let store = HKHealthStore()
        let cal = Calendar.current
        let now = Date()
        // Look back one extra day so the first morning's night (which starts the prior
        // evening) is fully covered by the sample window.
        guard let start = cal.date(byAdding: .day, value: -max(1, days), to: cal.startOfDay(for: now))
        else { return [:] }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: now, options: [])
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)

        struct Wire: Sendable {
            let day: Date; let source: String; let minutes: Int
            let value: HKCategoryValueSleepAnalysis
        }
        let wires: [Wire] = await withCheckedContinuation { cont in
            let q = HKSampleQuery(sampleType: sleepType, predicate: predicate,
                                  limit: HKObjectQueryNoLimit, sortDescriptors: [sort]) { _, results, _ in
                let samples = (results as? [HKCategorySample]) ?? []
                let mapped: [Wire] = samples.compactMap { s in
                    guard let value = HKCategoryValueSleepAnalysis(rawValue: s.value) else { return nil }
                    let minutes = Int(s.endDate.timeIntervalSince(s.startDate) / 60)
                    guard minutes > 0 else { return nil }
                    return Wire(day: cal.startOfDay(for: s.endDate),
                                source: s.sourceRevision.source.bundleIdentifier,
                                minutes: minutes,
                                value: value)
                }
                cont.resume(returning: mapped)
            }
            store.execute(q)
        }

        // Aggregate per night per source, then pick the best source for each night.
        var perNightPerSource: [Date: [String: NightSleep]] = [:]
        for w in wires {
            var bySource = perNightPerSource[w.day] ?? [:]
            var agg = bySource[w.source] ?? NightSleep()
            switch w.value {
            case .inBed:            agg.inBed += w.minutes
            case .awake:            agg.awake += w.minutes
            case .asleepDeep:       agg.deep += w.minutes;  agg.asleep += w.minutes
            case .asleepREM:        agg.rem += w.minutes;   agg.asleep += w.minutes
            case .asleepCore:       agg.core += w.minutes;  agg.asleep += w.minutes
            case .asleepUnspecified: agg.asleep += w.minutes
            @unknown default:       break
            }
            bySource[w.source] = agg
            perNightPerSource[w.day] = bySource
        }
        var out: [Date: NightSleep] = [:]
        for (day, bySource) in perNightPerSource {
            guard var best = bySource.values.max(by: {
                ($0.asleep, $0.inBed) < ($1.asleep, $1.inBed)
            }) else { continue }
            // Old-style sources report only "in bed" — fall back so the night still counts.
            if best.asleep == 0 { best.asleep = best.inBed }
            if best.asleep > 0 { out[day] = best }
        }
        return out
    }

    /// Backfill/refresh `SleepEntry` rows for the last `days` nights. Returns rows changed.
    @MainActor
    @discardableResult
    func importRecentSleep(days: Int = 14, into context: ModelContext, existing: [SleepEntry]) async -> Int {
        let perNight = await dailySleep(days: days)
        return HealthKitService.mergeDailySleep(perNight, into: context, existing: existing)
    }

    /// Upsert one `SleepEntry` per night. Pure of HealthKit so it's unit-testable: corrects a
    /// night whose totals changed (a bridge app syncing later in the day), inserts missing
    /// nights, never duplicates. Returns rows changed.
    @MainActor
    @discardableResult
    static func mergeDailySleep(_ perNight: [Date: NightSleep],
                                into context: ModelContext,
                                existing: [SleepEntry],
                                calendar: Calendar = .current) -> Int {
        guard !perNight.isEmpty else { return 0 }
        var changed = 0
        for (day, agg) in perNight {
            if let row = existing.first(where: { calendar.isDate($0.date, inSameDayAs: day) }) {
                if row.asleepMinutes != agg.asleep || row.inBedMinutes != agg.inBed
                    || row.deepMinutes != agg.deep || row.remMinutes != agg.rem
                    || row.coreMinutes != agg.core || row.awakeMinutes != agg.awake {
                    row.asleepMinutes = agg.asleep
                    row.inBedMinutes = agg.inBed
                    row.deepMinutes = agg.deep
                    row.remMinutes = agg.rem
                    row.coreMinutes = agg.core
                    row.awakeMinutes = agg.awake
                    changed += 1
                }
            } else {
                context.insert(SleepEntry(date: calendar.startOfDay(for: day),
                                          asleepMinutes: agg.asleep,
                                          inBedMinutes: agg.inBed,
                                          deepMinutes: agg.deep,
                                          remMinutes: agg.rem,
                                          coreMinutes: agg.core,
                                          awakeMinutes: agg.awake))
                changed += 1
            }
        }
        if changed > 0 { try? context.save() }
        return changed
    }

    // MARK: - Daily vitals (resting HR + HRV)

    /// Daily resting heart rate + HRV (SDNN) for the last `days` days. These are already
    /// daily-aggregate quantities in HealthKit (the tracker computes them from its raw
    /// stream), so a per-day average IS the "raw" signal at the right resolution.
    func dailyVitals(days: Int) async -> [Date: (rhr: Double, hrv: Double)] {
        guard Self.isAvailable else { return [:] }
        let rhr = await dailyAverage(.restingHeartRate, unit: HKUnit.count().unitDivided(by: .minute()), days: days)
        let hrv = await dailyAverage(.heartRateVariabilitySDNN, unit: .secondUnit(with: .milli), days: days)
        var out: [Date: (rhr: Double, hrv: Double)] = [:]
        for day in Set(rhr.keys).union(hrv.keys) {
            out[day] = (rhr[day] ?? 0, hrv[day] ?? 0)
        }
        return out
    }

    /// Daily discrete-average of a quantity type over the last `days` days.
    private func dailyAverage(_ id: HKQuantityTypeIdentifier, unit: HKUnit, days: Int) async -> [Date: Double] {
        guard let type = HKQuantityType.quantityType(forIdentifier: id) else { return [:] }
        let store = HKHealthStore()
        let cal = Calendar.current
        let now = Date()
        let anchor = cal.startOfDay(for: now)
        guard let start = cal.date(byAdding: .day, value: -(max(1, days) - 1), to: anchor) else { return [:] }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: now, options: .strictStartDate)
        var interval = DateComponents(); interval.day = 1
        return await withCheckedContinuation { cont in
            let q = HKStatisticsCollectionQuery(quantityType: type,
                                                quantitySamplePredicate: predicate,
                                                options: .discreteAverage,
                                                anchorDate: anchor,
                                                intervalComponents: interval)
            q.initialResultsHandler = { _, results, _ in
                var out: [Date: Double] = [:]
                results?.enumerateStatistics(from: start, to: now) { stat, _ in
                    if let v = stat.averageQuantity()?.doubleValue(for: unit), v > 0 {
                        out[cal.startOfDay(for: stat.startDate)] = v
                    }
                }
                cont.resume(returning: out)
            }
            store.execute(q)
        }
    }

    /// Backfill/refresh `VitalsEntry` rows for the last `days` days. Returns rows changed.
    @MainActor
    @discardableResult
    func importRecentVitals(days: Int = 14, into context: ModelContext, existing: [VitalsEntry]) async -> Int {
        let perDay = await dailyVitals(days: days)
        return HealthKitService.mergeDailyVitals(perDay, into: context, existing: existing)
    }

    /// Pure, testable upsert of daily vitals — same contract as the other merges.
    @MainActor
    @discardableResult
    static func mergeDailyVitals(_ perDay: [Date: (rhr: Double, hrv: Double)],
                                 into context: ModelContext,
                                 existing: [VitalsEntry],
                                 calendar: Calendar = .current) -> Int {
        guard !perDay.isEmpty else { return 0 }
        var changed = 0
        for (day, v) in perDay {
            if let row = existing.first(where: { calendar.isDate($0.date, inSameDayAs: day) }) {
                if row.restingHeartRate != v.rhr || row.hrvMs != v.hrv {
                    row.restingHeartRate = v.rhr
                    row.hrvMs = v.hrv
                    changed += 1
                }
            } else {
                context.insert(VitalsEntry(date: calendar.startOfDay(for: day),
                                           restingHeartRate: v.rhr, hrvMs: v.hrv))
                changed += 1
            }
        }
        if changed > 0 { try? context.save() }
        return changed
    }

    // MARK: - Detected workouts

    /// A plain, Sendable snapshot of an HKWorkout for crossing back to the main actor.
    struct ImportableWorkout: Sendable {
        let healthKitUUID: String
        let date: Date
        let activity: String
        let durationMinutes: Int
        let caloriesBurned: Double
        let sourceName: String
    }

    /// Workouts recorded by OTHER apps/devices (a tracker's auto-detection) in the last
    /// `days` days. Our own app never writes HKWorkouts, but the self-source filter keeps
    /// that invariant safe if it ever does.
    func recentDetectedWorkouts(days: Int) async -> [ImportableWorkout] {
        guard Self.isAvailable else { return [] }
        let store = HKHealthStore()
        let now = Date()
        guard let start = Calendar.current.date(byAdding: .day, value: -max(1, days), to: now)
        else { return [] }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: now, options: [])
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)
        let appSource = HKSource.default()

        return await withCheckedContinuation { cont in
            let q = HKSampleQuery(sampleType: .workoutType(), predicate: predicate,
                                  limit: HKObjectQueryNoLimit, sortDescriptors: [sort]) { _, results, _ in
                let workouts = (results as? [HKWorkout]) ?? []
                let mapped: [ImportableWorkout] = workouts.compactMap { w in
                    guard w.sourceRevision.source != appSource else { return nil }
                    let minutes = Int((w.duration / 60).rounded())
                    guard minutes >= 1 else { return nil }
                    let kcal = w.statistics(for: HKQuantityType(.activeEnergyBurned))?
                        .sumQuantity()?.doubleValue(for: .kilocalorie()) ?? 0
                    return ImportableWorkout(healthKitUUID: w.uuid.uuidString,
                                             date: w.startDate,
                                             activity: Self.activityLabel(w.workoutActivityType),
                                             durationMinutes: minutes,
                                             caloriesBurned: kcal,
                                             sourceName: w.sourceRevision.source.name)
                }
                cont.resume(returning: mapped)
            }
            store.execute(q)
        }
    }

    /// Insert any newly-detected workouts (deduped by HealthKit UUID, and against the
    /// direct Google Health pipe by time window — the same session seen through both
    /// pipes must land as ONE row, whichever pipe delivered first). Returns rows added.
    @MainActor
    @discardableResult
    func importRecentDetectedWorkouts(days: Int = 14,
                                      into context: ModelContext,
                                      existing: [DetectedWorkout]) async -> Int {
        let found = await recentDetectedWorkouts(days: days)
        let fresh = GoogleHealthSync.dedupAgainstExisting(found, existing: existing)
        return HealthKitService.mergeDetectedWorkouts(fresh, into: context, existing: existing)
    }

    /// Pure, testable merge: inserts workouts whose UUID isn't known yet; never duplicates.
    @MainActor
    @discardableResult
    static func mergeDetectedWorkouts(_ found: [ImportableWorkout],
                                      into context: ModelContext,
                                      existing: [DetectedWorkout]) -> Int {
        guard !found.isEmpty else { return 0 }
        let known = Set(existing.map(\.healthKitUUID))
        var added = 0
        for w in found where !known.contains(w.healthKitUUID) {
            context.insert(DetectedWorkout(healthKitUUID: w.healthKitUUID,
                                           date: w.date,
                                           activity: w.activity,
                                           durationMinutes: w.durationMinutes,
                                           caloriesBurned: w.caloriesBurned,
                                           sourceName: w.sourceName))
            added += 1
        }
        if added > 0 { try? context.save() }
        return added
    }

    /// Human label for the common tracker-detected activity types; anything exotic
    /// falls back to "Workout".
    static func activityLabel(_ type: HKWorkoutActivityType) -> String {
        switch type {
        case .running:                  return "Running"
        case .walking:                  return "Walking"
        case .hiking:                   return "Hiking"
        case .cycling:                  return "Cycling"
        case .swimming:                 return "Swimming"
        case .traditionalStrengthTraining, .functionalStrengthTraining:
                                        return "Strength training"
        case .highIntensityIntervalTraining: return "HIIT"
        case .yoga:                     return "Yoga"
        case .pilates:                  return "Pilates"
        case .elliptical:               return "Elliptical"
        case .rowing:                   return "Rowing"
        case .stairClimbing:            return "Stair climbing"
        case .socialDance, .cardioDance:  return "Dance"
        case .soccer:                   return "Soccer"
        case .basketball:               return "Basketball"
        case .tennis:                   return "Tennis"
        case .coreTraining:             return "Core training"
        case .flexibility:              return "Stretching"
        case .mixedCardio, .crossTraining: return "Cardio"
        default:                        return "Workout"
        }
    }
}
