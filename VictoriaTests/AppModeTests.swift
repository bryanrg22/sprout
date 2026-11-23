import XCTest
@testable import Victoria

/// Home and Gym: which surface a launch opens on, and that no stored value can leave
/// the app showing nothing.
final class AppModeTests: XCTestCase {

    func testStoredValueResolves() {
        XCTAssertEqual(AppMode.resolve(stored: "home"), .home)
        XCTAssertEqual(AppMode.resolve(stored: "gym"), .gym)
    }

    func testUnknownOrMissingStoredValueIsHome() {
        XCTAssertEqual(AppMode.resolve(stored: nil), .home)
        XCTAssertEqual(AppMode.resolve(stored: ""), .home)
        XCTAssertEqual(AppMode.resolve(stored: "GYM"), .home, "raw values are exact")
        XCTAssertEqual(AppMode.resolve(stored: "competition"), .home, "a mode from another version")
    }

    func testEveryModeRoundTripsThroughItsStoredValue() {
        for mode in AppMode.allCases {
            XCTAssertEqual(AppMode.resolve(stored: mode.rawValue), mode)
            XCTAssertFalse(mode.label.isEmpty)
        }
        XCTAssertEqual(AppMode.allCases.map(\.label), ["Home", "Gym"], "the order the switch shows them in")
    }

    func testANormalLaunchReopensWhereItWasLeft() {
        XCTAssertEqual(AppMode.initial(arguments: ["Victoria"], stored: "gym"), .gym)
        XCTAssertEqual(AppMode.initial(arguments: ["Victoria"], stored: "home"), .home)
        XCTAssertEqual(AppMode.initial(arguments: ["Victoria"], stored: nil), .home, "first launch")
        XCTAssertEqual(AppMode.initial(arguments: ["Victoria", "--seed-demo"], stored: "gym"), .gym)
    }

    func testADemoTabArgumentDecidesTheMode() {
        XCTAssertEqual(AppMode.initial(arguments: ["Victoria", "--demo-tab", "workouts"], stored: "home"), .gym)
        XCTAssertEqual(AppMode.initial(arguments: ["Victoria", "--demo-tab", "food"], stored: "gym"), .home,
                       "asking for a Home tab must show Home even if Gym was stored")
        XCTAssertEqual(AppMode.initial(arguments: ["Victoria", "--demo-tab", "coach"], stored: "gym"), .home)
        XCTAssertEqual(AppMode.initial(arguments: ["Victoria", "--demo-tab"], stored: "gym"), .gym,
                       "a dangling flag is ignored")
    }

    func testHomeTabFromDemoArgument() {
        XCTAssertEqual(HomeTab.initial(arguments: ["Victoria"]), .today)
        XCTAssertEqual(HomeTab.initial(arguments: ["Victoria", "--demo-tab", "food"]), .nutrients)
        XCTAssertEqual(HomeTab.initial(arguments: ["Victoria", "--demo-tab", "progress"]), .progress)
        XCTAssertEqual(HomeTab.initial(arguments: ["Victoria", "--demo-tab", "coach"]), .coach)
        XCTAssertEqual(HomeTab.initial(arguments: ["Victoria", "--demo-tab", "workouts"]), .today,
                       "workouts is a mode, so Home itself opens on Today")
        XCTAssertEqual(HomeTab.initial(arguments: ["Victoria", "--demo-tab", "nonsense"]), .today)
        XCTAssertEqual(HomeTab.initial(arguments: ["Victoria", "--demo-tab"]), .today)
    }

    func testHomeTabTagsAreDistinctAndTheCoachKeepsItsTag() {
        XCTAssertEqual(Set(HomeTab.allCases.map(\.rawValue)).count, HomeTab.allCases.count)
        XCTAssertEqual(HomeTab.coach.rawValue, 4)
        XCTAssertEqual(HomeTab.today.rawValue, 0)
    }

    func testAskingTheCoachAlwaysLandsOnTheCoachInHome() {
        let destination = AppMode.destinationForCoach()
        XCTAssertEqual(destination.mode, .home)
        XCTAssertEqual(destination.homeTab, .coach)
    }
}
