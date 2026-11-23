import XCTest
@testable import Victoria

/// The week card on Workouts: how many days of a calendar week had any activity, and what
/// each day held (EVAL_REPORT 28).
final class ActivityWeekTests: XCTestCase {

    private func calendar(firstWeekday: Int, zone: String = "America/Los_Angeles") -> Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: zone)!
        c.firstWeekday = firstWeekday
        return c
    }

    private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 12, _ cal: Calendar) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d, hour: h))!
    }

    private func e(_ d: Date, _ minutes: Int = 30) -> ActivityWeek.Entry { .init(date: d, minutes: minutes) }

    func testAWeekStartsOnTheCalendarsFirstDay() {
        let sunday = calendar(firstWeekday: 1)
        let monday = calendar(firstWeekday: 2)
        let wed = date(2026, 11, 25, 12, sunday)   // a Wednesday
        let us = ActivityWeek.containing(wed, logged: [], detected: [], now: wed, calendar: sunday)
        XCTAssertEqual(us.days.first?.date, sunday.startOfDay(for: date(2026, 11, 22, 12, sunday)), "Sunday first")
        let eu = ActivityWeek.containing(wed, logged: [], detected: [], now: wed, calendar: monday)
        XCTAssertEqual(eu.days.first?.date, monday.startOfDay(for: date(2026, 11, 23, 12, monday)), "Monday first")
        XCTAssertEqual(us.days.count, 7)
        XCTAssertEqual(Set(us.days.map(\.date)).count, 7)
    }

    func testADayIsActiveOnceWhateverItHeldAndEitherSourceCounts() {
        let cal = calendar(firstWeekday: 1)
        let now = date(2026, 11, 28, 20, cal)        // Saturday evening: the whole week is past
        let logged = [e(date(2026, 11, 22, 8, cal), 50), e(date(2026, 11, 22, 18, cal), 20),  // Sunday twice
                      e(date(2026, 11, 24, 7, cal), 32)]                                     // Tuesday
        let detected = [e(date(2026, 11, 24, 17, cal), 24),                                  // Tuesday again
                        e(date(2026, 11, 26, 17, cal), 45)]                                  // Thursday, tracker only
        let week = ActivityWeek.containing(now, logged: logged, detected: detected, now: now, calendar: cal)
        XCTAssertEqual(week.activeDays, 3, "Sunday, Tuesday and Thursday")
        XCTAssertEqual(week.days.map(\.isActive), [true, false, true, false, true, false, false])
        XCTAssertEqual(week.days[0].logged, 2)
        XCTAssertEqual(week.days[0].minutes, 70)
        XCTAssertEqual(week.days[2].logged, 1)
        XCTAssertEqual(week.days[2].detected, 1)
        XCTAssertEqual(week.days[2].minutes, 56)
        XCTAssertEqual(week.days[4].detected, 1, "a day the tracker saw is active with nothing logged")
    }

    func testWorkoutsOutsideTheWeekAndJustPastMidnightLandOnTheirOwnDays() {
        let cal = calendar(firstWeekday: 1)
        let now = date(2026, 11, 28, 12, cal)
        let logged = [e(date(2026, 11, 21, 23, cal)),          // Saturday before: previous week
                      e(cal.date(from: DateComponents(year: 2026, month: 11, day: 22, hour: 0, minute: 5))!),  // Sunday 00:05
                      e(date(2026, 11, 29, 9, cal))]           // Sunday after: next week
        let week = ActivityWeek.containing(now, logged: logged, detected: [], now: now, calendar: cal)
        XCTAssertEqual(week.activeDays, 1)
        XCTAssertTrue(week.days[0].isActive)
    }

    func testTodayAndTheDaysAfterItAreMarked() {
        let cal = calendar(firstWeekday: 1)
        let now = date(2026, 11, 24, 9, cal)                    // Tuesday morning
        let week = ActivityWeek.containing(now, logged: [], detected: [], now: now, calendar: cal)
        XCTAssertEqual(week.days.map(\.isToday), [false, false, true, false, false, false, false])
        XCTAssertEqual(week.days.map(\.isFuture), [false, false, false, true, true, true, true])
        XCTAssertTrue(week.containsToday)
        let earlier = ActivityWeek.containing(date(2026, 11, 17, 12, cal), logged: [], detected: [], now: now, calendar: cal)
        XCTAssertFalse(earlier.containsToday)
        XCTAssertFalse(earlier.days.contains(where: \.isFuture))
    }

    func testAWeekAcrossTheClockChangeStillHasSevenMidnights() {
        let cal = calendar(firstWeekday: 1)                     // US clocks went back on 2026-11-01
        let inside = date(2026, 11, 3, 12, cal)
        let week = ActivityWeek.containing(inside, logged: [e(date(2026, 11, 1, 3, cal))], detected: [],
                                           now: date(2026, 11, 20, 12, cal), calendar: cal)
        XCTAssertEqual(week.days.count, 7)
        for day in week.days { XCTAssertEqual(cal.startOfDay(for: day.date), day.date) }
        XCTAssertEqual(cal.component(.day, from: week.days[6].date), 7)
        XCTAssertTrue(week.days[0].isActive, "the 3 a.m. workout on the day the clocks changed")
    }

    func testNegativeMinutesNeverSubtract() {
        let cal = calendar(firstWeekday: 1)
        let now = date(2026, 11, 28, 12, cal)
        let week = ActivityWeek.containing(now, logged: [e(date(2026, 11, 23, 9, cal), -40), e(date(2026, 11, 23, 10, cal), 20)],
                                           detected: [], now: now, calendar: cal)
        XCTAssertEqual(week.days[1].minutes, 20)
    }

    func testVoiceOverSaysWhatEachDayHeld() {
        let cal = calendar(firstWeekday: 1)
        let monday = cal.startOfDay(for: date(2026, 11, 23, 12, cal))
        func day(_ logged: Int, _ detected: Int, _ minutes: Int, future: Bool = false) -> ActivityWeek.Day {
            .init(date: monday, logged: logged, detected: detected, minutes: minutes, isFuture: future, isToday: false)
        }
        let name = monday.formatted(.dateTime.weekday(.wide).month(.wide).day())
        XCTAssertEqual(ActivityWeek.spokenLabel(for: day(0, 0, 0)), "\(name), no activity")
        XCTAssertEqual(ActivityWeek.spokenLabel(for: day(0, 0, 0, future: true)), "\(name), not yet")
        XCTAssertEqual(ActivityWeek.spokenLabel(for: day(1, 0, 50)), "\(name), active: 1 workout logged, 50 minutes")
        XCTAssertEqual(ActivityWeek.spokenLabel(for: day(2, 1, 0)), "\(name), active: 2 workouts logged, 1 tracked")
    }

    func testTheDayIdentifierIsTheLocalDate() {
        let cal = calendar(firstWeekday: 1)
        XCTAssertEqual(AccessibilityID.Workouts.weekDay(date(2026, 11, 3, 23, cal), calendar: cal),
                       "workouts.week.day.2026-11-03")
    }
}
