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
}
