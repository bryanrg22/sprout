import Foundation
import HealthKit
import SwiftData

extension HealthKitService {
    /// Today's cumulative step count from Apple Health (0 if unavailable/unauthorized).
    func todaySteps() async -> Double {
        guard Self.isAvailable,
              let stepType = HKQuantityType.quantityType(forIdentifier: .stepCount) else { return 0 }
        let store = HKHealthStore()
        let start = Calendar.current.startOfDay(for: Date())
        let predicate = HKQuery.predicateForSamples(withStart: start, end: Date(), options: .strictStartDate)
        return await withCheckedContinuation { cont in
            let q = HKStatisticsQuery(quantityType: stepType,
                                      quantitySamplePredicate: predicate,
                                      options: .cumulativeSum) { _, stats, _ in
                cont.resume(returning: stats?.sumQuantity()?.doubleValue(for: .count()) ?? 0)
            }
            store.execute(q)
        }
    }

    /// Pull today's steps from Health and upsert a `StepsEntry` for today.
    @MainActor
    @discardableResult
    func importTodaySteps(into context: ModelContext, existing: [StepsEntry]) async -> Int {
        let steps = Int(await todaySteps())
        guard steps > 0 else { return 0 }
        let today = Calendar.current.startOfDay(for: Date())
        if let row = existing.first(where: { Calendar.current.isDate($0.date, inSameDayAs: today) }) {
            row.count = steps
        } else {
            context.insert(StepsEntry(date: today, count: steps))
        }
        try? context.save()
        return steps
    }

    /// Per-day cumulative step totals for the last `days` days (keyed by start-of-day), read
    /// from Apple Health as a daily-bucketed statistics collection. This is the FULL total for
    /// each day — unlike `importTodaySteps`, which only ever captured "today so far."
    func dailySteps(days: Int) async -> [Date: Int] {
        guard Self.isAvailable,
              let stepType = HKQuantityType.quantityType(forIdentifier: .stepCount) else { return [:] }
        let store = HKHealthStore()
        let cal = Calendar.current
        let now = Date()
        let anchor = cal.startOfDay(for: now)
        guard let start = cal.date(byAdding: .day, value: -(max(1, days) - 1), to: anchor) else { return [:] }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: now, options: .strictStartDate)
        var interval = DateComponents(); interval.day = 1
        return await withCheckedContinuation { cont in
            let q = HKStatisticsCollectionQuery(quantityType: stepType,
                                                quantitySamplePredicate: predicate,
                                                options: .cumulativeSum,
                                                anchorDate: anchor,
                                                intervalComponents: interval)
            q.initialResultsHandler = { _, results, _ in
                var out: [Date: Int] = [:]
                results?.enumerateStatistics(from: start, to: now) { stat, _ in
                    let c = Int((stat.sumQuantity()?.doubleValue(for: .count()) ?? 0).rounded())
                    if c > 0 { out[cal.startOfDay(for: stat.startDate)] = c }
                }
                cont.resume(returning: out)
            }
            store.execute(q)
        }
    }

    /// Backfill / correct `StepsEntry` for the last `days` days from Apple Health's REAL
    /// per-day totals (upsert one row per day). This fixes the weekly average, which used to
    /// read partial or missing historical days. Returns the number of rows changed.
    @MainActor
    @discardableResult
    func importRecentSteps(days: Int = 30, into context: ModelContext, existing: [StepsEntry]) async -> Int {
        let perDay = await dailySteps(days: days)
        return HealthKitService.mergeDailySteps(perDay, into: context, existing: existing)
    }

    /// Upsert one `StepsEntry` per day from real per-day step totals. Pure of HealthKit so it is
    /// unit-testable: it corrects a day whose count changed (the frozen-partial-day bug), inserts
    /// a missing day, leaves unchanged days alone, and never creates a duplicate row. Returns the
    /// number of rows changed.
    @MainActor
    @discardableResult
    static func mergeDailySteps(_ perDay: [Date: Int],
                                into context: ModelContext,
                                existing: [StepsEntry],
                                calendar: Calendar = .current) -> Int {
        guard !perDay.isEmpty else { return 0 }
        var changed = 0
        for (day, count) in perDay {
            if let row = existing.first(where: { calendar.isDate($0.date, inSameDayAs: day) }) {
                if row.count != count { row.count = count; changed += 1 }   // correct a partial/stale day
            } else {
                context.insert(StepsEntry(date: calendar.startOfDay(for: day), count: count))
                changed += 1
            }
        }
        if changed > 0 { try? context.save() }
        return changed
    }
}
