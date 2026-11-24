import Foundation
import SwiftData
import XCTest
@testable import Sprout

/// The columns of the settings matrix (`docs/settings-dependencies.md`): everything the app
/// derives from what the user can change.
enum SettingsColumn: String, CaseIterable, Hashable {
    /// The daily calorie target, its range, and the Today ring's target with the step bonus.
    case calories
    /// Protein, carbs and fat targets.
    case macros
    /// The water goal in ounces and in her containers.
    case water
    /// The plan's "goals changed since this plan was built" flag.
    case planFlag
    /// `calorieTargetOverride`, `calorieMaxOverride`, `proteinTargetOverride`.
    case overrides
    /// The settings-dependent fields of the widget snapshot.
    case widget
    /// The coach's whole system prompt and the tool schemas sent with it.
    case coach
    /// The settings-dependent fields of the snapshot published to a buddy.
    case buddy
    /// The topic and headline today's brief would be given (before the per-day cache).
    case brief
    /// The prompt today's checklist would be built from (before the per-day cache).
    case checklist
    /// The achievements the data earns.
    case achievements
}

/// One user ("Alex") in an in-memory store on the production schema, with enough logged data
/// that every derived value has room to move in both directions.
///
/// **Dates.** Rows are placed relative to one instant captured when the world is made. The
/// builders under test (`CoachContext.summary`, `BuddyStateComposer`, `AchievementCatalog`,
/// `WidgetDataWriter.snapshot`) decide "today" from the device clock and take no date, so a
/// fixture on fixed dates would never have a "today". A run that straddles midnight between
/// making the world and reading it can fail; nothing else here depends on the clock.
///
/// **The numbers** (weights in lb; kg = lb / 2.20462):
/// - male, 180 cm, 30 years old, moderately active (×1.55), relaxed loss pace (−250 kcal),
///   start 200, goal 180;
/// - weigh-ins 202, 201, 200 at 15, 8 and 1 days ago → trend 200.503
///   (EWMA, 7-day smoothing: 202 → 201.368 → 200.503), about −0.75 lb/week;
/// - BMR = 10 × 90.947 + 6.25 × 180 − 5 × 30 + 5 = 1889.47; TDEE = 2928.68; target = 2678.68;
/// - protein 1.8 g/kg = 164 g, fat 0.8 g/kg = 73 g, carbs fill the rest;
/// - water with no goal of her own: 0.5 oz × 200 lb start weight = 100 oz = 6 bottles of 16.9 oz;
/// - food: 2600, 2600, 2800 kcal on the last three days, and 163 g of protein today;
/// - 97 oz of water yesterday; 9000 steps today against a goal of 8000.
@MainActor
final class SettingsWorld {
    let container: ModelContainer
    let context: ModelContext
    let profile: UserProfile
    let now: Date
    private(set) var plan: CoachPlan?

    /// The plan the "plan active" world starts with: written for a loss goal.
    static let planFloor = 2300.0
    static let planCeiling = 2500.0
    static let planProtein = 180.0

    init(withPlan: Bool) throws {
        container = try TestStore.makeContainer()
        context = ModelContext(container)
        now = Date()
        let cal = Calendar.current

        let p = UserProfile()
        p.name = "Alex"
        p.sex = .male
        p.heightCm = 180
        // Thirty and a half years ago, so the whole-year age is 30 on any day the test runs.
        p.birthDate = cal.date(byAdding: DateComponents(year: -30, month: -6), to: now)!
        p.activityLevel = .moderate
        p.pace = .relaxed
        p.startWeightLbs = 200
        p.goalWeightLbs = 180
        p.dailyStepGoal = 8000
        p.stepsAdjustCalories = false
        p.waterGoalOzOverride = 0
        p.waterContainerOz = 16.9
        p.waterContainerLabel = "bottle"
        p.themeStyle = .cute
        p.onboardingComplete = true
        context.insert(p)
        profile = p

        func daysAgo(_ days: Int, hours: Int = 1) -> Date {
            cal.date(byAdding: DateComponents(day: -days, hour: -hours), to: now)!
        }
        context.insert(WeightEntry(date: daysAgo(15), weightLbs: 202))
        context.insert(WeightEntry(date: daysAgo(8), weightLbs: 201))
        context.insert(WeightEntry(date: daysAgo(1), weightLbs: 200))

        context.insert(FoodEntry(date: daysAgo(3, hours: 0), mealType: .dinner, name: "Day three",
                                 calories: 2600, proteinG: 150, carbsG: 300, fatG: 85))
        context.insert(FoodEntry(date: daysAgo(2, hours: 0), mealType: .dinner, name: "Day two",
                                 calories: 2600, proteinG: 150, carbsG: 300, fatG: 85))
        context.insert(FoodEntry(date: daysAgo(1, hours: 0), mealType: .dinner, name: "Day one",
                                 calories: 2800, proteinG: 150, carbsG: 330, fatG: 90))
        context.insert(FoodEntry(date: now, mealType: .snack, name: "Protein shake",
                                 calories: 700, proteinG: 163, carbsG: 10, fatG: 1))
        context.insert(WaterEntry(date: daysAgo(1, hours: 0), amountOz: 97))
        context.insert(StepsEntry(date: cal.startOfDay(for: now), count: 9000))

        if withPlan {
            let built = CoachPlan(headline: "Lose to 180", assessment: "On track.",
                                  strategy: "Hold a small deficit.",
                                  calorieMin: Self.planFloor, calorieMax: Self.planCeiling,
                                  proteinTarget: Self.planProtein, goalSummary: "Lose to 180",
                                  timeframe: "by summer", dataPointsAtBuild: 9)
            context.insert(built)
            built.anchorTargets(to: .lose)          // what `PlanService.generate` records
            plan = built
            PlanTargetSync.apply(plan: built, to: p)   // what `RootView.syncPlanTargets` does at launch
        }
        try context.save()
    }

    /// Removes the UserDefaults entries the plan's flag and direction record leave behind.
    func tearDown() {
        guard let plan else { return }
        plan.clearGoalsChanged()
        plan.caloriesDirection = nil
        plan.proteinDirection = nil
    }

    // MARK: - Reading the store

    var weights: [WeightEntry] { fetch(sortBy: [SortDescriptor(\WeightEntry.date)]) }
    var foods: [FoodEntry] { fetch(sortBy: [SortDescriptor(\FoodEntry.date)]) }
    var water: [WaterEntry] { fetch(sortBy: [SortDescriptor(\WaterEntry.date)]) }
    var steps: [StepsEntry] { fetch(sortBy: [SortDescriptor(\StepsEntry.date)]) }
    var basisWeight: Double { profile.basisWeightLbs(weights: weights) }
    var todaySteps: Int { steps.first { Calendar.current.isDateInToday($0.date) }?.count ?? 0 }

    private func fetch<T: PersistentModel>(sortBy: [SortDescriptor<T>]) -> [T] {
        (try? context.fetch(FetchDescriptor<T>(sortBy: sortBy))) ?? []
    }

    // MARK: - The two surfaces a setting is changed from

    /// A change made in Settings: the control writes the profile, and the Form's
    /// `.onChange(of: PlanGoalInputs(profile))` calls `PlanGoalInputs.profileChanged`
    /// (`SettingsView.swift`). The call is made here whatever changed; it does nothing when
    /// no plan input did.
    func inSettings(_ change: (UserProfile) -> Void) {
        let before = PlanGoalInputs(profile)
        change(profile)
        PlanGoalInputs.profileChanged(from: before, profile: profile, context: context)
        try? context.save()
    }

    /// A change made by the coach: the tool call is parsed and applied exactly as
    /// `CoachView.handleTurn` does it. Returns the undo, when the tool has one.
    @discardableResult
    func viaCoach(_ tool: String, _ input: [String: Any],
                  file: StaticString = #filePath, line: UInt = #line) -> CoachTools.Applied? {
        switch CoachTools.parse(name: tool, input: input, profile: profile,
                                todaysFoods: CoachContext.todaysFoods(foods),
                                currentWeightLbs: TrendCalculator.currentTrend(weights)) {
        case .ok(let request):
            return CoachTools.applyReturningUndo(request, to: profile, context: context)
        case .invalid(let reason):
            XCTFail("\(tool) was rejected: \(reason)", file: file, line: line)
            return nil
        }
    }

    /// A weigh-in saved from the Progress tab (`WeightView.save(weight:)`): one inserted row.
    func weighIn(_ lbs: Double) {
        context.insert(WeightEntry(date: now, weightLbs: lbs))
        try? context.save()
    }

    /// A plan built on Progress, reduced to what `PlanService.generate` does to the store
    /// once the model has answered: the row, the direction record, a cleared flag, the targets.
    func buildPlan(floor: Double, ceiling: Double, protein: Double) {
        let built = plan ?? CoachPlan()
        built.calorieMin = floor
        built.calorieMax = ceiling
        built.proteinTarget = protein
        built.headline = "Rebuilt"
        built.updatedAt = now
        if plan == nil { context.insert(built) }
        plan = built
        try? context.save()
        built.clearGoalsChanged()
        built.anchorTargets(to: profile.pace.direction)
        PlanTargetSync.apply(plan: built, to: profile)
    }

    // MARK: - Everything derived, one string per column

    func derived() -> [SettingsColumn: String] {
        let weights = weights, foods = foods, water = water, steps = steps
        let basis = profile.basisWeightLbs(weights: weights)
        var out: [SettingsColumn: String] = [:]

        out[.calories] = [
            "target \(n(profile.dailyCalorieTarget(weightLbs: basis)))",
            "range \(profile.calorieGoalText(weightLbs: basis))",
            "ring \(n(profile.dailyTargetWithSteps(weightLbs: basis, steps: todaySteps)))",
        ].joined(separator: " | ")

        let macros = profile.macroTargets(weightLbs: basis)
        out[.macros] = "P \(n(macros.proteinG)) C \(n(macros.carbsG)) F \(n(macros.fatG))"

        out[.water] = "\(n(profile.waterTargetOz)) oz = \(profile.waterGoalContainers) × \(profile.waterContainerLabel) of \(n(profile.waterContainerOz)) oz"

        out[.planFlag] = plan.map { $0.goalsChangedSinceBuild ? "flagged" : "clear" } ?? "no plan"

        out[.overrides] = "\(n(profile.calorieTargetOverride)) / \(n(profile.calorieMaxOverride)) / \(n(profile.proteinTargetOverride))"

        let snap = WidgetDataWriter.snapshot(profile: profile, foods: foods, weights: weights,
                                             waters: water, steps: steps)
        out[.widget] = [
            "name \(snap.name)", "theme \(snap.themeStyleRaw)", "avatar \(snap.companionAvatarRaw)",
            "kcal \(n(snap.calorieTarget))–\(n(snap.calorieMax)) bonus \(n(snap.stepBonus))",
            "P \(n(snap.proteinTarget)) C \(n(snap.carbsTarget)) F \(n(snap.fatTarget))",
            "steps goal \(snap.stepGoal)", "water goal \(n(snap.waterGoalOz))",
            "trend \(n(snap.trendWeight ?? -1)) rate \(n(snap.ratePerWeek)) goal \(n(snap.goalWeight))",
        ].joined(separator: " | ")

        let schemas = CoachTools.schemas(for: profile)
        let schemaText = (try? JSONSerialization.data(withJSONObject: schemas, options: [.sortedKeys]))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "unserialisable"
        out[.coach] = CoachContext.system(profile: profile, foods: foods, weights: weights,
                                          water: water, steps: steps, plan: plan)
            + "\n# tools\n" + schemaText

        let buddy = BuddyStateComposer.compose(profile: profile, foods: foods, water: water,
                                               steps: steps, sessions: [], weights: weights)
        out[.buddy] = [
            "name \(buddy.displayName)", "shares \(buddy.sharesFullData)",
            "steps goal \(buddy.stepGoal)", "water goal \(n(buddy.waterGoal))",
            "trend \(n(buddy.trendWeightLbs)) rate \(n(buddy.weeklyRateLbs)) goal \(n(buddy.goalWeightLbs))",
            "kcal \(n(buddy.calorieTarget))",
            "P \(n(buddy.proteinTarget)) C \(n(buddy.carbTarget)) F \(n(buddy.fatTarget))",
        ].joined(separator: " | ")

        var signals = DailyBriefService.Signals()
        signals.name = profile.name
        signals.trendEasedDown = DailyBriefCard.trendEasedDown(
            direction: profile.pace.direction, ratePerWeek: TrendCalculator.ratePerWeek(weights))
        let picked = DailyBriefService.pick(signals)
        out[.brief] = "\(picked.topic.rawValue): \(picked.headline)"

        out[.checklist] = ChecklistPlanService.userPrompt(
            name: profile.name, direction: profile.pace.direction,
            dataSummary: CoachContext.summary(profile: profile, foods: foods, weights: weights,
                                              water: water),
            bio: profile.onboardingNote, memoryNotes: "")

        out[.achievements] = AchievementCatalog.newlyEarned(
            foods: foods, weights: weights, water: water, steps: steps, workouts: [],
            profile: profile, alreadyUnlocked: []).map(\.id).sorted().joined(separator: ",")

        return out
    }

    private func n(_ value: Double) -> String { String(format: "%.2f", value) }
}

/// One row of the matrix: change one input, and say which columns must move. Every other
/// column must come out exactly as it went in.
@MainActor
extension XCTestCase {

    /// - Parameters:
    ///   - moves: the columns that must change.
    ///   - conditional: columns that change for some values of the input and not others;
    ///     not asserted here, each has its own test.
    func assertRow(_ label: String, in world: SettingsWorld,
                   moves: Set<SettingsColumn>, conditional: Set<SettingsColumn> = [],
                   file: StaticString = #filePath, line: UInt = #line,
                   change: () throws -> Void) rethrows {
        let before = world.derived()
        try change()
        let after = world.derived()
        for column in SettingsColumn.allCases where !conditional.contains(column) {
            let moved = before[column] != after[column]
            if moves.contains(column) {
                XCTAssertTrue(moved, "\(label): \(column.rawValue) should have moved and is still \(before[column] ?? "nil")",
                              file: file, line: line)
            } else {
                XCTAssertFalse(moved, "\(label): \(column.rawValue) should not move.\n  before: \(Self.firstDifference(before[column], after[column]).0)\n  after:  \(Self.firstDifference(before[column], after[column]).1)",
                               file: file, line: line)
            }
        }
    }

    /// The first line on which two long texts differ, so a failure is readable.
    static func firstDifference(_ a: String?, _ b: String?) -> (String, String) {
        let left = (a ?? "nil").components(separatedBy: "\n"), right = (b ?? "nil").components(separatedBy: "\n")
        for index in 0..<max(left.count, right.count) {
            let l = index < left.count ? left[index] : "<end>", r = index < right.count ? right[index] : "<end>"
            if l != r { return (String(l.prefix(300)), String(r.prefix(300))) }
        }
        return ("same", "same")
    }
}
