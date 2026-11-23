import SwiftData
import XCTest
@testable import Victoria

/// EVAL_REPORT 3, L-B7: the coach's `set_units` relabelled every weight "kg" without
/// converting, and the next weigh-in typed in kg was stored as pounds.
///
/// The app has no kg conversion (`docs/settings-dependencies.md` lists the 40-odd places a
/// real one has to cover), so metric is declined: the tool stays, answers that kilograms
/// aren't supported yet, and writes nothing; and every weight label is "lb", including for
/// a profile that was switched to metric before this.
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

    // MARK: - set_units

    func testSwitchingToMetricIsDeclinedAndChangesNothing() throws {
        let w = try SettingsWorld(withPlan: false)
        let request = try parsed("set_units", ["system": "metric"], w.profile)
        let applied = CoachTools.applyReturningUndo(request, to: w.profile, context: w.context)

        XCTAssertEqual(w.profile.unitSystem, .imperial)
        XCTAssertFalse(applied.changed)
        XCTAssertNil(applied.undo, "there is nothing to undo")
        XCTAssertTrue(applied.message.contains("Kilograms aren't supported yet"), applied.message)
        XCTAssertTrue(applied.resultText.hasPrefix("Not applied."), applied.resultText)
        XCTAssertEqual(try TestStore.fetchAll(UserProfile.self, in: w.container).first?.unitSystemRaw, "imperial")
    }

    /// The request still parses (the evaluation dataset's "switch the app to metric" case
    /// resolves to `setUnits`), and it is answered at once: a confirm card for something
    /// that will be declined would be a second lie.
    func testAMetricRequestStillParsesAndNeedsNoConfirm() throws {
        let profile = UserProfile()
        let metric = try parsed("set_units", ["system": "metric"], profile)
        XCTAssertEqual(metric.name, .setUnits)
        XCTAssertFalse(metric.requiresConfirm)
        guard case .setUnits(.metric) = metric.action else { return XCTFail("not a setUnits(.metric) action") }

        let imperial = try parsed("set_units", ["system": "imperial"], profile)
        XCTAssertTrue(imperial.requiresConfirm, "a real change of units is still confirmed")
    }

    func testAProfileStoredAsMetricCanSwitchBackToImperial() throws {
        let w = try SettingsWorld(withPlan: false)
        w.profile.unitSystem = .metric
        let request = try parsed("set_units", ["system": "imperial"], w.profile)
        let applied = CoachTools.applyReturningUndo(request, to: w.profile, context: w.context)
        XCTAssertTrue(applied.changed)
        XCTAssertEqual(w.profile.unitSystem, .imperial)
        XCTAssertEqual(applied.resultText, "Applied. Units are now imperial (lb).")
    }

    func testTheToolDescriptionSaysOnlyPoundsWork() throws {
        let text = try schemaText(UserProfile())
        XCTAssertTrue(text.contains("kilograms aren't supported yet"))
        XCTAssertFalse(text.contains("This changes only how weights are displayed"),
                       "the old description promised a display change that corrupted data")
    }

    // MARK: - No weight is ever labelled kg

    func testTheWeightUnitIsPoundsForBothSystems() {
        XCTAssertEqual(UnitSystem.imperial.weightUnit, "lb")
        XCTAssertEqual(UnitSystem.metric.weightUnit, "lb",
                       "weights are stored in pounds and nothing converts: a kg label would be false")
    }

    /// The defect itself, end to end, on a profile that was already switched to metric:
    /// the coach is told pounds, so "72" is not offered as a weigh-in, and what is logged
    /// is stored as the pounds it was described as.
    func testAMetricProfileIsStillAskedForAndShownPounds() throws {
        let w = try SettingsWorld(withPlan: false)
        w.profile.unitSystem = .metric

        let tools = try schemaText(w.profile)
        XCTAssertTrue(tools.contains("Their weight today in lb."))
        XCTAssertTrue(tools.contains("The new goal weight in lb."))
        XCTAssertTrue(tools.contains("The corrected starting weight in lb."))
        // ("in kg" alone would match the example request quoted in set_units' own description.)
        for asksForKilograms in ["weight today in kg", "goal weight in kg", "starting weight in kg", "and 500 kg"] {
            XCTAssertFalse(tools.contains(asksForKilograms), "a tool still asks for kilograms: \(asksForKilograms)")
        }

        let context = CoachContext.summary(profile: w.profile, foods: w.foods, weights: w.weights)
        XCTAssertTrue(context.contains("Goal weight: 180 lb"))
        XCTAssertTrue(context.contains("Current weight trend: 201 lb"))
        XCTAssertFalse(context.contains(" kg"), "the coach is told a pound value is kilograms")

        // 72 "kg" is below the 50–500 lb range only by luck of the number; 72 is in range,
        // so the range cannot be what protects her. The label is.
        let request = try parsed("log_weight", ["weight": 158.7], w.profile)
        XCTAssertEqual(request.confirmSummary, "log today's weigh-in at 158.7 lb")
        let applied = CoachTools.applyReturningUndo(request, to: w.profile, context: w.context)
        XCTAssertTrue(applied.message.contains("158.7 lb"), applied.message)
        XCTAssertEqual(w.weights.last?.weightLbs, 158.7)
    }

    func testRangeAndConfirmationMessagesNamePounds() throws {
        let profile = UserProfile()
        profile.unitSystem = .metric
        profile.startWeightLbs = 200
        profile.pace = .relaxed
        for tool in ["log_weight", "set_weight_goal", "set_start_weight"] {
            guard case .invalid(let reason) = CoachTools.parse(name: tool, input: ["weight": 30], profile: profile) else {
                XCTFail("\(tool) accepted 30"); continue
            }
            XCTAssertTrue(reason.contains("50–500 lb"), "\(tool): \(reason)")
            XCTAssertFalse(reason.contains("kg"), "\(tool): \(reason)")
        }
        XCTAssertEqual(try parsed("set_weight_goal", ["weight": 170], profile).confirmSummary,
                       "set your goal weight to 170 lb")
        XCTAssertEqual(try parsed("set_start_weight", ["weight": 195], profile).confirmSummary,
                       "correct your starting weight to 195 lb")
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
