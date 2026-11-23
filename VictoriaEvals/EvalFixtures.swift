import Foundation
@testable import Victoria

/// The two synthetic users every coach eval runs against. Fixed values, no randomness
/// and no real person's data: a result must be reproducible from the dataset alone.
@MainActor
enum EvalFixtures {

    struct User {
        let profile: UserProfile
        let foods: [FoodEntry]
        let weights: [WeightEntry]
        let water: [WaterEntry]
    }

    static func user(_ key: String) -> User {
        let gaining = key == "gain"
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)

        let p = UserProfile()
        p.name = gaining ? "Alex" : "Sam"
        p.sex = gaining ? .male : .female
        p.birthDate = calendar.date(byAdding: .year, value: -27, to: today) ?? today
        p.heightCm = gaining ? 178 : 165
        p.startWeightLbs = gaining ? 158 : 162
        p.goalWeightLbs = gaining ? 172 : 145
        p.activityLevel = .light
        p.pace = gaining ? .leanGain : .relaxed
        p.unitSystem = .imperial
        p.waterContainerOz = 16.9
        p.waterContainerLabel = "bottle"
        p.dailyStepGoal = 8000
        p.onboardingComplete = true

        func at(_ hour: Int) -> Date { calendar.date(bySettingHour: hour, minute: 15, second: 0, of: today) ?? today }
        let foods = [
            FoodEntry(date: at(8), mealType: .breakfast, name: "Greek yogurt", calories: 150,
                      proteinG: 17, carbsG: 9, fatG: 4),
            FoodEntry(date: at(12), mealType: .lunch, name: "Chicken burrito bowl", calories: 720,
                      proteinG: 45, carbsG: 78, fatG: 24),
        ]
        let base = gaining ? 160.0 : 158.0
        let weights = (0..<10).map { day in
            WeightEntry(date: calendar.date(byAdding: .day, value: -day, to: today) ?? today,
                        weightLbs: base + (gaining ? -0.2 : 0.2) * Double(day))
        }
        let water = [WaterEntry(date: at(9), amountOz: 16.9)]
        return User(profile: p, foods: foods, weights: weights, water: water)
    }
}
