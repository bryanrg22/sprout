import Foundation
import SwiftData
import WidgetKit

/// Builds a `WidgetSnapshot` from SwiftData and writes it to the shared App Group,
/// then asks WidgetKit to reload. Call on app launch/foreground and after the
/// mutations that change today's numbers (logging food, water, a weigh-in).
enum WidgetDataWriter {

    @MainActor
    static func refresh(context: ModelContext, profile: UserProfile?) {
        guard let profile else { return }
        let cal = Calendar.current

        let foods   = (try? context.fetch(FetchDescriptor<FoodEntry>())) ?? []
        let weights = (try? context.fetch(FetchDescriptor<WeightEntry>(sortBy: [SortDescriptor(\.date)]))) ?? []
        let waters  = (try? context.fetch(FetchDescriptor<WaterEntry>())) ?? []
        let steps   = (try? context.fetch(FetchDescriptor<StepsEntry>())) ?? []

        let todayFood = foods.filter { cal.isDateInToday($0.date) }
        let eaten   = todayFood.reduce(0) { $0 + $1.totalCalories }
        let protein = todayFood.reduce(0) { $0 + $1.totalProteinG }
        let carbs   = todayFood.reduce(0) { $0 + $1.totalCarbsG }
        let fat     = todayFood.reduce(0) { $0 + $1.totalFatG }

        let trend = TrendCalculator.currentTrend(weights)
        let basis = trend ?? (profile.startWeightLbs > 0 ? profile.startWeightLbs : 150)
        let stepCount = steps.first { cal.isDateInToday($0.date) }?.count ?? 0
        let stepBonus = profile.stepBonusCalories(weightLbs: basis, steps: stepCount)
        let target = profile.dailyCalorieTarget(weightLbs: basis) + stepBonus
        let macros = profile.macroTargets(weightLbs: basis)
        let waterToday = waters.filter { cal.isDateInToday($0.date) }.reduce(0) { $0 + $1.amountOz }
        let spark = Array(TrendCalculator.trend(weights).suffix(14).map(\.value))

        let snap = WidgetSnapshot(
            updated: .now,
            name: profile.name.isEmpty ? "Your" : profile.name.capitalized,
            themeStyleRaw: profile.themeStyle.rawValue,            // so the widget paints in her/his skin
            companionAvatarRaw: profile.companionAvatar.rawValue,  // so the widget shows the right buddy
            calorieTarget: target,
            caloriesEaten: eaten,
            stepBonus: stepBonus,
            protein: protein, proteinTarget: macros.proteinG,
            carbs: carbs, carbsTarget: macros.carbsG,
            fat: fat, fatTarget: macros.fatG,
            steps: stepCount, stepGoal: profile.dailyStepGoal,
            waterOz: waterToday, waterGoalOz: profile.waterTargetOz,
            trendWeight: trend, ratePerWeek: TrendCalculator.ratePerWeek(weights),
            goalWeight: profile.goalWeightLbs,
            trendSpark: spark,
            streak: streak(foods: foods, weights: weights, steps: steps, calendar: cal)
        )
        WidgetSharedStore.save(snap)
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// Consecutive days (back from today) with any logged activity.
    private static func streak(foods: [FoodEntry], weights: [WeightEntry],
                               steps: [StepsEntry], calendar cal: Calendar) -> Int {
        var days = Set(foods.map { cal.startOfDay(for: $0.date) })
        days.formUnion(weights.map { cal.startOfDay(for: $0.date) })
        days.formUnion(steps.map { cal.startOfDay(for: $0.date) })
        var count = 0
        var day = cal.startOfDay(for: .now)
        while days.contains(day) {
            count += 1
            guard let prev = cal.date(byAdding: .day, value: -1, to: day) else { break }
            day = prev
        }
        return count
    }
}
