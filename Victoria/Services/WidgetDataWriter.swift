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
        let calRange = profile.calorieGoalRange(weightLbs: basis)
        let calMax = calRange.high.isFinite ? calRange.high + stepBonus : 0   // 0 = single-number (gain) goal
        let macros = profile.macroTargets(weightLbs: basis)
        let waterToday = waters.filter { cal.isDateInToday($0.date) }.reduce(0) { $0 + $1.amountOz }
        let spark = Array(TrendCalculator.trend(weights).suffix(14).map(\.value))

        // The custom character reaches the widget as a small file beside the snapshot; the
        // snapshot names its digest. A built-in character removes any file left from before.
        let avatar = profile.companionAvatar
        let avatarDigest = WidgetAvatarFile.sync(sourcePNG: avatar == .custom ? profile.customAvatarPNG : nil,
                                                 in: WidgetAvatarFile.defaultDirectory)

        let snap = WidgetSnapshot(
            updated: .now,
            // First name only — the widget is narrow and a full name truncates ("Bryan Ramir…").
            name: profile.name.isEmpty ? "Your"
                : (profile.name.split(separator: " ").first.map(String.init) ?? profile.name).capitalized,
            themeStyleRaw: profile.themeStyle.rawValue,            // so the widget paints in her/his skin
            companionAvatarRaw: avatar.rawValue,                   // so the widget shows the right buddy
            companionAvatarDigest: avatarDigest,
            calorieTarget: target,
            calorieMax: calMax,
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
            // Active logging only (food/water/manual weigh-in) — NOT auto-imported steps or
            // scale-synced weights, which would otherwise inflate the streak. See StreakCalculator.
            streak: StreakCalculator.loggingStreak(foods: foods, waters: waters, weights: weights, calendar: cal)
        )
        WidgetSharedStore.save(snap)
        WidgetCenter.shared.reloadAllTimelines()
    }
}
