import XCTest

/// t. The weekly competition in the Buddy hub (EVAL_REPORT 29), against the simulator's
/// local mock buddy (`--demo-buddy` starts it paired). The buddy's record is fixed
/// (`LocalMockSyncService.sampleCompetition`); this phone's comes from the seeded profile.
final class CompetitionFlowTests: SproutUITestCase {

    func testTheCardShowsBothScoresLastWeekAndADaysTargets() throws {
        app.launchArguments = ["--ui-testing", "--ui-test-fresh-defaults", "--seed-demo", "--demo-gain",
                               "--demo-buddy", "--demo-screen", "buddy"]
        app.launch()

        let card = app.descendants(matching: .any)[AccessibilityID.Competition.card]
        wait("the competition card") { card.exists }
        let score = app.descendants(matching: .any)[AccessibilityID.Competition.score]
        // The hub is long: scroll the page (not the card, which is off screen) until the
        // score line can be touched.
        var swipes = 0
        while !(score.exists && score.isHittable), swipes < 8 {
            app.swipeUp()
            swipes += 1
        }
        XCTAssertTrue(score.isHittable, "the score line came on screen after \(swipes) swipes")
        XCTAssertTrue(score.label.hasPrefix("This week: you "), score.label)
        XCTAssertTrue(score.label.contains("points"), score.label)
        XCTAssertNotNil(firstInteger(in: score.label), score.label)

        // The mock buddy finished last week with 20 points.
        let lastWeek = app.descendants(matching: .any)[AccessibilityID.Competition.lastWeek]
        XCTAssertTrue(lastWeek.exists)
        XCTAssertTrue(lastWeek.label.contains("– 20"), lastWeek.label)

        // The buddy (Sam) always has Monday played: 3 points, for calories, water and active.
        let monday = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@ AND label ENDSWITH %@",
                                                      "Sam, Monday", "3 points, calories in range, water, active")).firstMatch
        wait("the buddy's Monday") { monday.exists }
        monday.tap()
        let detail = app.descendants(matching: .any)[AccessibilityID.Competition.dayDetail]
        wait("the day's targets") { detail.exists }
        XCTAssertTrue(detail.label.contains("3 of 5"), detail.label)
        monday.tap()
        wait("the detail to close") { !detail.exists }
    }
}
