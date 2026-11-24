import SwiftData
import XCTest
@testable import Sprout

/// Kilograms, and the defect that kept them out (EVAL_REPORT 3, L-B7; EVAL_REPORT 31).
///
/// The defect: `set_units` relabelled every weight "kg" without converting, and the next
/// weigh-in typed in kg was stored as pounds. The rule now: every weight is STORED in pounds
/// in both systems; metric converts what is shown and what is typed, at the edge, so a value
/// typed in kg is stored as the pounds it equals, and switching units never changes a
/// stored value.
@MainActor
final class UnitsSafetyTests: XCTestCase {

    private func parsed(_ tool: String, _ input: [String: Any], _ profile: UserProfile,
                        file: StaticString = #filePath, line: UInt = #line) throws -> CoachTools.ParsedRequest {
        guard case .ok(let request) = CoachTools.parse(name: tool, input: input, profile: profile) else {
            XCTFail("\(tool) was rejected", file: file, line: line)
            throw XCTSkip("unreachable")
        }
        return request
    }

    private func schemaText(_ profile: UserProfile) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: CoachTools.schemas(for: profile), options: [.sortedKeys])
        return String(decoding: data, as: UTF8.self)
    }

    // MARK: - The conversion

    func testTheConversionIsTheInternationalPound() {
        XCTAssertEqual(UnitSystem.kilogramsPerPound, 0.45359237)
        XCTAssertEqual(UnitSystem.metric.display(100), 45.359237, accuracy: 1e-9)
        XCTAssertEqual(UnitSystem.metric.pounds(fromDisplay: 72), 158.733, accuracy: 0.001)
        XCTAssertEqual(UnitSystem.imperial.display(158.7), 158.7)
        XCTAssertEqual(UnitSystem.imperial.pounds(fromDisplay: 158.7), 158.7)
        for lbs in [50.0, 123.4, 200.5032, 500] {
            XCTAssertEqual(UnitSystem.metric.pounds(fromDisplay: UnitSystem.metric.display(lbs)), lbs, accuracy: 1e-9)
        }
    }

    func testTheUnitAndTheFormattedText() {
        XCTAssertEqual(UnitSystem.imperial.weightUnit, "lb")
        XCTAssertEqual(UnitSystem.metric.weightUnit, "kg")
        XCTAssertEqual(UnitSystem.imperial.format(156.44), "156.4 lb")
        XCTAssertEqual(UnitSystem.metric.format(156.44), "71.0 kg")
        XCTAssertEqual(UnitSystem.metric.format(180, decimals: 0), "82 kg")
        XCTAssertEqual(UnitSystem.imperial.formatRate(-0.64), "0.6 lb/wk")
        XCTAssertEqual(UnitSystem.metric.formatRate(-1.0), "0.5 kg/wk")
        XCTAssertEqual(GoalPace.relaxed.subtitle(in: .metric), "About 0.2 kg / week")
        XCTAssertEqual(GoalPace.steady.subtitle(in: .metric), "About 0.5 kg / week")
        XCTAssertEqual(GoalPace.relaxed.subtitle(in: .imperial), "About 0.5 lb / week")
        XCTAssertEqual(GoalPace.maintain.subtitle(in: .metric), "Hold steady")
    }

    // MARK: - set_units

    func testSwitchingToMetricAppliesAndChangesNoStoredValue() throws {
        let w = try SettingsWorld(withPlan: false)
        let goal = w.profile.goalWeightLbs, start = w.profile.startWeightLbs
        let weights = w.weights.map(\.weightLbs)
        let request = try parsed("set_units", ["system": "metric"], w.profile)
        XCTAssertTrue(request.requiresConfirm, "a change of units is confirmed, both ways")
        let applied = CoachTools.applyReturningUndo(request, to: w.profile, context: w.context)

        XCTAssertTrue(applied.changed)
        XCTAssertEqual(applied.message, "Units are now metric (kg).")
        XCTAssertEqual(w.profile.unitSystem, .metric)
        XCTAssertEqual(w.profile.goalWeightLbs, goal)
        XCTAssertEqual(w.profile.startWeightLbs, start)
        XCTAssertEqual(try TestStore.fetchAll(WeightEntry.self, in: w.container).map(\.weightLbs).sorted(), weights.sorted())
        applied.undo?()
        XCTAssertEqual(w.profile.unitSystem, .imperial)
        XCTAssertEqual(w.profile.goalWeightLbs, goal)
    }

    func testAMetricProfileCanSwitchBackToImperial() throws {
        let w = try SettingsWorld(withPlan: false)
        w.profile.unitSystem = .metric
        let applied = CoachTools.applyReturningUndo(try parsed("set_units", ["system": "imperial"], w.profile),
                                                    to: w.profile, context: w.context)
        XCTAssertTrue(applied.changed)
        XCTAssertEqual(w.profile.unitSystem, .imperial)
        XCTAssertEqual(applied.resultText, "Applied. Units are now imperial (lb).")
    }

    func testTheToolDescriptionSaysMetricWorksAndNothingStoredChanges() throws {
        let text = try schemaText(UserProfile())
        XCTAssertFalse(text.contains("kilograms aren't supported yet"))
        XCTAssertTrue(text.contains("Metric shows and takes weights in kilograms"))
        XCTAssertTrue(text.contains("No logged value is ever altered"))
    }

    // MARK: - The defect, end to end, the right way round now

    /// A metric profile is asked for and told kilograms, and a weigh-in said as 72 kg is
    /// stored as the 158.7 lb it equals, not as 72 lb (which was L-B7).
    func testAMetricProfileIsAskedInKilogramsAndStoresPounds() throws {
        let w = try SettingsWorld(withPlan: false)
        w.profile.unitSystem = .metric

        let tools = try schemaText(w.profile)
        XCTAssertTrue(tools.contains("Their weight today in kg."))
        XCTAssertTrue(tools.contains("The new goal weight in kg."))
        XCTAssertTrue(tools.contains("The corrected starting weight in kg."))

        let context = CoachContext.summary(profile: w.profile, foods: w.foods, weights: w.weights)
        XCTAssertTrue(context.contains("Goal weight: 82 kg"), "180 lb is 81.6 kg")
        XCTAssertTrue(context.contains("Current weight trend: 91 kg"), "200.5 lb is 90.9 kg")
        XCTAssertFalse(context.contains(" lb"), "a metric profile is never told pounds")

        let request = try parsed("log_weight", ["weight": 72], w.profile)
        XCTAssertEqual(request.confirmSummary, "log today's weigh-in at 72 kg")
        let before = Set(try TestStore.fetchAll(WeightEntry.self, in: w.container).map(\.persistentModelID))
        let applied = CoachTools.applyReturningUndo(request, to: w.profile, context: w.context)
        XCTAssertEqual(applied.message, "Logged today's weigh-in: 72 kg. Remember, the trend is what matters.")
        let added = try TestStore.fetchAll(WeightEntry.self, in: w.container).filter { !before.contains($0.persistentModelID) }
        XCTAssertEqual(added.count, 1)
        XCTAssertEqual(try XCTUnwrap(added.first).weightLbs, 158.733, accuracy: 0.001, "72 kg stored as pounds, never as 72 lb")
    }

    func testGoalAndStartWeightsAreTakenInTheShownUnit() throws {
        let w = try SettingsWorld(withPlan: false)
        w.profile.unitSystem = .metric
        let goal = try parsed("set_weight_goal", ["weight": 80], w.profile)
        XCTAssertEqual(goal.confirmSummary, "set your goal weight to 80 kg")
        _ = CoachTools.applyReturningUndo(goal, to: w.profile, context: w.context)
        XCTAssertEqual(w.profile.goalWeightLbs, 176.37, accuracy: 0.01)

        let start = try parsed("set_start_weight", ["weight": 95], w.profile)
        XCTAssertEqual(start.confirmSummary, "correct your starting weight to 95 kg")
        _ = CoachTools.applyReturningUndo(start, to: w.profile, context: w.context)
        XCTAssertEqual(w.profile.startWeightLbs, 209.44, accuracy: 0.01)
    }

    func testTheRangeIsTheSamePoundsSaidInTheShownUnit() throws {
        let metric = UserProfile()
        metric.unitSystem = .metric
        metric.startWeightLbs = 200
        metric.pace = .relaxed
        for tool in ["log_weight", "set_weight_goal", "set_start_weight"] {
            guard case .invalid(let reason) = CoachTools.parse(name: tool, input: ["weight": 20], profile: metric) else {
                XCTFail("\(tool) accepted 20 kg (44 lb)"); continue
            }
            XCTAssertTrue(reason.contains("23–227 kg"), "\(tool): \(reason)")
            XCTAssertFalse(reason.contains(" lb"), "\(tool): \(reason)")
        }
        // 30 kg is 66 lb: inside 50–500 lb, so it is accepted in metric (it was refused in pounds).
        if case .invalid(let reason) = CoachTools.parse(name: "log_weight", input: ["weight": 30], profile: metric) {
            XCTFail("30 kg is in range: \(reason)")
        }
        let imperial = UserProfile()
        guard case .invalid(let reason) = CoachTools.parse(name: "log_weight", input: ["weight": 30], profile: imperial) else {
            return XCTFail("30 lb accepted")
        }
        XCTAssertTrue(reason.contains("50–500 lb"), reason)
    }

    func testAGoalOnTheWrongSideIsExplainedInTheShownUnit() throws {
        let p = UserProfile()
        p.unitSystem = .metric
        p.startWeightLbs = 200
        p.pace = .relaxed
        guard case .invalid(let reason) = CoachTools.parse(name: "set_weight_goal", input: ["weight": 95], profile: p) else {
            return XCTFail("a goal above the current weight was accepted for a loss goal")
        }
        XCTAssertTrue(reason.contains("your current 90.7 kg"), reason)
    }

    // MARK: - The other places a weight is shown

    func testTheSettingsFooterIsInTheShownUnit() {
        let text = SettingsCopy.goalsFooter(startWeightLbs: 200, goalWeightLbs: 180, currentWeightLbs: 195,
                                            pace: .relaxed, source: .calculated, units: .metric)
        XCTAssertTrue(text.hasPrefix("Started at 91 kg → aiming for 82 kg at a relaxed pace."), text)
    }

    func testTheWidgetGetsWeightsInTheShownUnitAndSaysWhichUnit() throws {
        let w = try SettingsWorld(withPlan: false)
        w.profile.unitSystem = .metric
        let snap = WidgetDataWriter.snapshot(profile: w.profile, foods: w.foods, weights: w.weights,
                                             waters: [], steps: [])
        XCTAssertEqual(snap.weightUnit, "kg")
        XCTAssertEqual(try XCTUnwrap(snap.trendWeight), 90.9, accuracy: 0.1)
        XCTAssertEqual(snap.goalWeight, 81.6, accuracy: 0.1)

        w.profile.unitSystem = .imperial
        let lb = WidgetDataWriter.snapshot(profile: w.profile, foods: w.foods, weights: w.weights, waters: [], steps: [])
        XCTAssertEqual(lb.weightUnit, "lb")
        XCTAssertEqual(lb.goalWeight, 180)
    }

    func testAWidgetSnapshotWrittenBeforeTheUnitDecodesAsPounds() throws {
        var dict = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(WidgetSnapshot.placeholder)) as? [String: Any])
        dict.removeValue(forKey: "weightUnit")
        let old = try JSONDecoder().decode(WidgetSnapshot.self, from: JSONSerialization.data(withJSONObject: dict))
        XCTAssertEqual(old.weightUnit, "lb")
    }

    /// Height was never affected: it is stored in centimetres and the tool takes centimetres.
    func testHeightIsCentimetresInAndOut() throws {
        let w = try SettingsWorld(withPlan: false)
        let request = try parsed("set_height", ["cm": 182], w.profile)
        XCTAssertEqual(request.confirmSummary, "set your height to 182 cm")
        _ = CoachTools.applyReturningUndo(request, to: w.profile, context: w.context)
        XCTAssertEqual(w.profile.heightCm, 182)
    }
}
