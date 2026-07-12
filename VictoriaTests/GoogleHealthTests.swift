import XCTest
import SwiftData
@testable import Victoria

/// Pins the Google Health API v4 wire format (verified against Google's discovery doc,
/// rev 2026-07-08) and the OAuth plumbing that never touches the network:
/// int64-as-string fields, "1234s" durations, {year,month,day} civil dates, stage
/// mapping (LIGHT→core), nap exclusion, best-session-per-night, cross-source workout
/// dedup, PKCE (RFC 7636 test vector), and the reversed-client-ID redirect.
final class GoogleHealthTests: XCTestCase {

    private func json(_ s: String) -> [[String: Any]] {
        // swiftlint:disable:next force_try force_cast
        try! JSONSerialization.jsonObject(with: Data(s.utf8)) as! [[String: Any]]
    }

    // MARK: - Sleep parsing

    /// Field names + string-int64 values exactly as the API sends them.
    private let stagesNight = """
    [{
      "name": "users/me/dataTypes/sleep/dataPoints/123",
      "dataSource": {"platform": "FITBIT", "device": {"displayName": "Fitbit Air"}},
      "sleep": {
        "type": "STAGES",
        "interval": {
          "startTime": "2026-07-08T06:30:00Z",
          "endTime": "2026-07-08T14:30:00Z",
          "startUtcOffset": "-25200s",
          "endUtcOffset": "-25200s",
          "civilEndTime": {"date": {"year": 2026, "month": 7, "day": 8},
                           "time": {"hours": 7, "minutes": 30}}
        },
        "stages": [],
        "summary": {
          "minutesInSleepPeriod": "480",
          "minutesAsleep": "420",
          "minutesAwake": "60",
          "stagesSummary": [
            {"type": "DEEP",  "count": "5",  "minutes": "104"},
            {"type": "LIGHT", "count": "32", "minutes": "205"},
            {"type": "REM",   "count": "11", "minutes": "75"},
            {"type": "AWAKE", "count": "30", "minutes": "60"}
          ]
        },
        "metadata": {"nap": false, "processed": true, "stagesStatus": "SUCCEEDED"}
      }
    }]
    """

    func testParsesStagedNightWithStringInt64s() {
        let out = GoogleHealthClient.parseSleep(dataPoints: json(stagesNight))
        XCTAssertEqual(out.count, 1)
        let night = out.values.first!
        XCTAssertEqual(night.asleep, 420)
        XCTAssertEqual(night.inBed, 480)
        XCTAssertEqual(night.deep, 104)
        XCTAssertEqual(night.core, 205)   // Google LIGHT lands in Apple's "core" bucket
        XCTAssertEqual(night.rem, 75)
        XCTAssertEqual(night.awake, 60)
        // Keyed by the civil wake date, local start-of-day.
        let cal = Calendar.current
        let expected = cal.startOfDay(for: cal.date(from: DateComponents(year: 2026, month: 7, day: 8))!)
        XCTAssertEqual(out.keys.first, expected)
    }

    func testNapIsExcluded() {
        let nap = stagesNight.replacingOccurrences(of: "\"nap\": false", with: "\"nap\": true")
        XCTAssertTrue(GoogleHealthClient.parseSleep(dataPoints: json(nap)).isEmpty)
    }

    func testLongestSessionPerNightWins() {
        let short = stagesNight
            .replacingOccurrences(of: "\"minutesAsleep\": \"420\"", with: "\"minutesAsleep\": \"90\"")
        let both = json(stagesNight) + json(short)
        let out = GoogleHealthClient.parseSleep(dataPoints: both)
        XCTAssertEqual(out.count, 1)
        XCTAssertEqual(out.values.first?.asleep, 420)
        // Order-independent: reversed input picks the same winner.
        let reversed = GoogleHealthClient.parseSleep(dataPoints: both.reversed())
        XCTAssertEqual(reversed.values.first?.asleep, 420)
    }

    /// No civilEndTime → wake day derived from endTime shifted by the session's own
    /// UTC offset. 2026-07-08T06:59:00Z at -07:00 is 23:59 on July 7 LOCAL TO THE
    /// TRACKER — the night belongs to July 7, not the UTC date.
    func testWakeDayFallsBackToUtcOffsetMath() {
        let noCivil = """
        [{"sleep": {
            "type": "CLASSIC",
            "interval": {"startTime": "2026-07-08T04:00:00Z",
                         "endTime": "2026-07-08T06:59:00Z",
                         "endUtcOffset": "-25200s"},
            "summary": {"minutesAsleep": "160", "minutesInSleepPeriod": "179"},
            "metadata": {"nap": false}
        }}]
        """
        let out = GoogleHealthClient.parseSleep(dataPoints: json(noCivil))
        let cal = Calendar.current
        let expected = cal.startOfDay(for: cal.date(from: DateComponents(year: 2026, month: 7, day: 7))!)
        XCTAssertEqual(out.keys.first, expected)
    }

    func testClassicNightWithoutSummaryFallsBackToStageSegments() {
        let segmentsOnly = """
        [{"sleep": {
            "type": "CLASSIC",
            "interval": {"civilEndTime": {"date": {"year": 2026, "month": 7, "day": 8}}},
            "stages": [
              {"type": "ASLEEP", "startTime": "2026-07-08T05:00:00Z", "endTime": "2026-07-08T07:00:00Z"},
              {"type": "AWAKE",  "startTime": "2026-07-08T07:00:00Z", "endTime": "2026-07-08T07:30:00Z"}
            ],
            "metadata": {"nap": false}
        }}]
        """
        let out = GoogleHealthClient.parseSleep(dataPoints: json(segmentsOnly))
        let night = out.values.first
        XCTAssertEqual(night?.asleep, 120)   // AWAKE segment not counted as sleep…
        XCTAssertEqual(night?.awake, 30)     // …but it IS counted as awake time,
        XCTAssertEqual(night?.inBed, 150)    // so the in-bed total comes out right.
    }

    /// Totals-only wire shape: a summary with a sleep period but no asleep minutes must
    /// still count as a night (mirrors the HealthKit path's in-bed fallback).
    func testPeriodOnlySummaryFallsBackToInBed() {
        let periodOnly = """
        [{"sleep": {
            "type": "CLASSIC",
            "interval": {"civilEndTime": {"date": {"year": 2026, "month": 7, "day": 8}}},
            "summary": {"minutesInSleepPeriod": "410"},
            "metadata": {"nap": false}
        }}]
        """
        let out = GoogleHealthClient.parseSleep(dataPoints: json(periodOnly))
        XCTAssertEqual(out.values.first?.asleep, 410)
        XCTAssertEqual(out.values.first?.inBed, 410)
    }

    func testGarbageSleepPointIsSkippedNotFatal() {
        let garbage = "[{\"sleep\": {\"summary\": {\"minutesAsleep\": \"nonsense\"}}}, {\"steps\": {}}]"
        XCTAssertTrue(GoogleHealthClient.parseSleep(dataPoints: json(garbage)).isEmpty)
    }

    // MARK: - Vitals parsing

    func testParsesVitalsAndJoinsByDay() {
        let rhr = """
        [{"dailyRestingHeartRate": {"date": {"year": 2026, "month": 7, "day": 9},
                                    "beatsPerMinute": "56"}}]
        """
        let hrv = """
        [{"dailyHeartRateVariability": {"date": {"year": 2026, "month": 7, "day": 9},
                                        "averageHeartRateVariabilityMilliseconds": 42.5}},
         {"dailyHeartRateVariability": {"date": {"year": 2026, "month": 7, "day": 8},
                                        "averageHeartRateVariabilityMilliseconds": 39.0}}]
        """
        let out = GoogleHealthClient.parseVitals(rhrPoints: json(rhr), hrvPoints: json(hrv))
        XCTAssertEqual(out.count, 2)
        let cal = Calendar.current
        let day9 = cal.startOfDay(for: cal.date(from: DateComponents(year: 2026, month: 7, day: 9))!)
        let day8 = cal.startOfDay(for: cal.date(from: DateComponents(year: 2026, month: 7, day: 8))!)
        XCTAssertEqual(out[day9]?.rhr, 56)        // string int64 → Double
        XCTAssertEqual(out[day9]?.hrv, 42.5)
        XCTAssertEqual(out[day8]?.rhr, 0)         // HRV-only day: rhr stays 0 (same as HealthKit path)
        XCTAssertEqual(out[day8]?.hrv, 39.0)
    }

    // MARK: - Exercise parsing

    func testParsesExerciseSession() {
        let points = """
        [{
          "name": "users/me/dataTypes/exercise/dataPoints/2026443605080188808",
          "dataSource": {"platform": "FITBIT", "device": {"displayName": "Fitbit Air"}},
          "exercise": {
            "exerciseType": "TRAIL_RUN",
            "displayName": "Trail run",
            "activeDuration": "1920s",
            "interval": {"startTime": "2026-07-09T17:00:00Z", "endTime": "2026-07-09T17:35:00Z"},
            "metricsSummary": {"caloriesKcal": 315.5, "steps": "4200",
                               "averageHeartRateBeatsPerMinute": "142"}
          }
        }]
        """
        let out = GoogleHealthClient.parseExercises(dataPoints: json(points))
        XCTAssertEqual(out.count, 1)
        let w = out[0]
        XCTAssertEqual(w.healthKitUUID, "ghealth:users/me/dataTypes/exercise/dataPoints/2026443605080188808")
        XCTAssertEqual(w.activity, "Running")           // TRAIL_RUN maps to the family label
        XCTAssertEqual(w.durationMinutes, 32)           // activeDuration 1920s, not the 35-min interval
        XCTAssertEqual(w.caloriesBurned, 315.5)
        XCTAssertEqual(w.sourceName, "Fitbit Air")
        XCTAssertEqual(w.date, GoogleHealthClient.rfc3339("2026-07-09T17:00:00Z"))
    }

    func testActivityLabelFallbacks() {
        XCTAssertEqual(GoogleHealthClient.activityLabel(type: "SPINNING", displayName: nil), "Cycling")
        XCTAssertEqual(GoogleHealthClient.activityLabel(type: "PADDLEBOARDING", displayName: "Paddleboard"),
                       "Paddleboard")                    // unmapped → API display name
        XCTAssertEqual(GoogleHealthClient.activityLabel(type: "CIRCUIT_TRAINING", displayName: nil),
                       "Circuit training")               // unmapped, no display name → prettified enum
        XCTAssertEqual(GoogleHealthClient.activityLabel(type: "OTHER", displayName: nil), "Workout")
        XCTAssertEqual(GoogleHealthClient.activityLabel(type: nil, displayName: nil), "Workout")
    }

    /// Same rounding contract as the HealthKit path: <30s rounds to 0 minutes → dropped
    /// (30s rounds up to 1 and is kept, exactly like an HKWorkout would be).
    func testSubMinuteExerciseIsDropped() {
        let blip = """
        [{"exercise": {"exerciseType": "WALKING", "activeDuration": "20s",
                       "interval": {"startTime": "2026-07-09T17:00:00Z"}}}]
        """
        XCTAssertTrue(GoogleHealthClient.parseExercises(dataPoints: json(blip)).isEmpty)
    }

    // MARK: - Cross-source workout dedup

    private func importable(_ minutesAgo: Int, duration: Int) -> HealthKitService.ImportableWorkout {
        HealthKitService.ImportableWorkout(healthKitUUID: "ghealth:x\(minutesAgo)",
                                           date: Date(timeIntervalSinceNow: Double(-minutesAgo * 60)),
                                           activity: "Running", durationMinutes: duration,
                                           caloriesBurned: 100, sourceName: "Fitbit")
    }

    func testDedupDropsSameSessionSeenThroughApplHealthBridge() {
        let google = importable(60, duration: 30)
        // Same session already imported via HealthKit (bridge app): starts 5 min off, similar length.
        let bridged = DetectedWorkout(healthKitUUID: UUID().uuidString,
                                      date: google.date.addingTimeInterval(5 * 60),
                                      activity: "Running", durationMinutes: 28,
                                      caloriesBurned: 95, sourceName: "Health Sync")
        let out = GoogleHealthSync.dedupAgainstExisting([google], existing: [bridged])
        XCTAssertTrue(out.isEmpty)
    }

    /// The dedup is SYMMETRIC: a HealthKit candidate must also be dropped when the same
    /// session already landed through the Google pipe first (both pipes live).
    func testDedupDropsHealthKitCandidateAgainstExistingGoogleRow() {
        let hkCandidate = HealthKitService.ImportableWorkout(
            healthKitUUID: UUID().uuidString,
            date: Date(timeIntervalSinceNow: -3600),
            activity: "Running", durationMinutes: 30,
            caloriesBurned: 100, sourceName: "Health Sync")
        let googleRow = DetectedWorkout(healthKitUUID: "ghealth:users/me/dataTypes/exercise/dataPoints/1",
                                        date: hkCandidate.date.addingTimeInterval(-4 * 60),
                                        activity: "Running", durationMinutes: 31,
                                        caloriesBurned: 104, sourceName: "Fitbit Air")
        XCTAssertTrue(GoogleHealthSync.dedupAgainstExisting([hkCandidate], existing: [googleRow]).isEmpty)
        // Same-pipe rows are NOT window-deduped (exact-ID dedup owns that case).
        let hkRow = DetectedWorkout(healthKitUUID: UUID().uuidString,
                                    date: hkCandidate.date,
                                    activity: "Running", durationMinutes: 30,
                                    caloriesBurned: 100, sourceName: "Health Sync")
        XCTAssertEqual(GoogleHealthSync.dedupAgainstExisting([hkCandidate], existing: [hkRow]).count, 1)
    }

    func testDedupKeepsDistinctWorkoutsAndIgnoresOwnGoogleRows() {
        let google = importable(60, duration: 30)
        // A different workout 2h earlier, and a ghealth row at the same time (mergeDetectedWorkouts
        // handles exact-ID dedup for those — the window rule must not eat them).
        let other = DetectedWorkout(healthKitUUID: UUID().uuidString,
                                    date: google.date.addingTimeInterval(-2 * 3600),
                                    activity: "Yoga", durationMinutes: 30,
                                    caloriesBurned: 80, sourceName: "Watch")
        let ownGoogle = DetectedWorkout(healthKitUUID: "ghealth:x60",
                                        date: google.date,
                                        activity: "Running", durationMinutes: 30,
                                        caloriesBurned: 100, sourceName: "Fitbit")
        let out = GoogleHealthSync.dedupAgainstExisting([google], existing: [other, ownGoogle])
        XCTAssertEqual(out.count, 1)
    }

    // MARK: - Vitals overlay (0 never beats a real reading)

    func testOverlayVitalsBackfillsMissingHalvesFromExistingRows() {
        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)
        // Existing row (e.g. from HealthKit): RHR 60, HRV 45.
        let row = VitalsEntry(date: today, restingHeartRate: 60, hrvMs: 45)
        // Google delivered HRV only for the day — its rhr would be 0.
        let google: [Date: (rhr: Double, hrv: Double)] = [today: (rhr: 0, hrv: 42)]
        let out = GoogleHealthSync.overlayVitals(google, onto: [row])
        XCTAssertEqual(out[today]?.rhr, 60, "existing RHR survives a Google HRV-only day")
        XCTAssertEqual(out[today]?.hrv, 42, "Google's fresh HRV still wins")
        // Full Google day: overlay must not touch it.
        let full: [Date: (rhr: Double, hrv: Double)] = [today: (rhr: 55, hrv: 50)]
        XCTAssertEqual(GoogleHealthSync.overlayVitals(full, onto: [row])[today]?.rhr, 55)
        // No existing row: passes through unchanged.
        XCTAssertEqual(GoogleHealthSync.overlayVitals(google, onto: [])[today]?.rhr, 0)
    }

    // MARK: - Integration: wire JSON → parse → merge → SwiftData rows

    /// The full ingestion path minus the network: parse real wire shapes, merge into an
    /// in-memory store, run it TWICE (launch + foreground do exactly this) and prove
    /// idempotence — same rows, updated in place, never duplicated.
    @MainActor
    func testEndToEndParseAndMergeIsIdempotent() throws {
        let schema = Schema([SleepEntry.self, DetectedWorkout.self, VitalsEntry.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let ctx = ModelContext(try ModelContainer(for: schema, configurations: config))

        let sleepPoints = json(stagesNight)
        let exercisePoints = json("""
        [{"name": "users/me/dataTypes/exercise/dataPoints/42",
          "exercise": {"exerciseType": "WALKING", "activeDuration": "1800s",
                       "interval": {"startTime": "2026-07-08T20:00:00Z"}}}]
        """)
        let rhrPoints = json("""
        [{"dailyRestingHeartRate": {"date": {"year": 2026, "month": 7, "day": 8},
                                    "beatsPerMinute": "57"}}]
        """)

        for pass in 1...2 {
            let sleep = GoogleHealthClient.parseSleep(dataPoints: sleepPoints)
            let existingSleep = try ctx.fetch(FetchDescriptor<SleepEntry>())
            HealthKitService.mergeDailySleep(sleep, into: ctx, existing: existingSleep)

            let vitals = GoogleHealthClient.parseVitals(rhrPoints: rhrPoints, hrvPoints: [])
            let existingVitals = try ctx.fetch(FetchDescriptor<VitalsEntry>())
            HealthKitService.mergeDailyVitals(
                GoogleHealthSync.overlayVitals(vitals, onto: existingVitals),
                into: ctx, existing: existingVitals)

            let workouts = GoogleHealthClient.parseExercises(dataPoints: exercisePoints)
            let existingWorkouts = try ctx.fetch(FetchDescriptor<DetectedWorkout>())
            HealthKitService.mergeDetectedWorkouts(
                GoogleHealthSync.dedupAgainstExisting(workouts, existing: existingWorkouts),
                into: ctx, existing: existingWorkouts)

            let sleepRows = try ctx.fetch(FetchDescriptor<SleepEntry>())
            let vitalsRows = try ctx.fetch(FetchDescriptor<VitalsEntry>())
            let workoutRows = try ctx.fetch(FetchDescriptor<DetectedWorkout>())
            XCTAssertEqual(sleepRows.count, 1, "pass \(pass): one night, never duplicated")
            XCTAssertEqual(vitalsRows.count, 1, "pass \(pass)")
            XCTAssertEqual(workoutRows.count, 1, "pass \(pass)")
            XCTAssertEqual(sleepRows[0].asleepMinutes, 420)
            XCTAssertEqual(sleepRows[0].deepMinutes, 104)
            XCTAssertTrue(sleepRows[0].hasStages)
            XCTAssertEqual(vitalsRows[0].restingHeartRate, 57)
            XCTAssertEqual(workoutRows[0].healthKitUUID,
                           "ghealth:users/me/dataTypes/exercise/dataPoints/42")
            XCTAssertEqual(workoutRows[0].durationMinutes, 30)
        }
    }

    /// The exact launch sequence that motivated the context-refetch fix: HealthKit
    /// inserts a night first (bridge/Watch), THEN the Google pass merges the same
    /// night against FRESH rows — it must update that row, not add a second one.
    @MainActor
    func testGoogleAfterHealthKitUpdatesInPlaceNeverDuplicates() throws {
        let schema = Schema([SleepEntry.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let ctx = ModelContext(try ModelContainer(for: schema, configurations: config))
        let cal = Calendar.current
        let night = cal.startOfDay(for: cal.date(from: DateComponents(year: 2026, month: 7, day: 8))!)

        // HealthKit pass: totals-only night from a bridge.
        HealthKitService.mergeDailySleep([night: .init(asleep: 400, inBed: 430)],
                                         into: ctx, existing: [])
        // Google pass, as refresh() now does it: re-fetch existing FIRST.
        let google = GoogleHealthClient.parseSleep(dataPoints: json(stagesNight))
        let fresh = try ctx.fetch(FetchDescriptor<SleepEntry>())
        HealthKitService.mergeDailySleep(google, into: ctx, existing: fresh)

        let rows = try ctx.fetch(FetchDescriptor<SleepEntry>())
        XCTAssertEqual(rows.count, 1, "same night through two pipes = one row")
        XCTAssertEqual(rows[0].asleepMinutes, 420, "Google's richer numbers won")
        XCTAssertTrue(rows[0].hasStages)
    }

    // MARK: - OAuth plumbing (no network)

    /// RFC 7636 appendix B test vector — the S256 challenge must match byte-for-byte.
    func testPKCEChallengeMatchesRFC7636Vector() {
        XCTAssertEqual(
            GoogleHealthAuth.codeChallenge(for: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"),
            "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
    }

    func testCodeVerifierIsUnpaddedBase64URLAndLongEnough() {
        let v = GoogleHealthAuth.makeCodeVerifier()
        XCTAssertGreaterThanOrEqual(v.count, 43)   // RFC 7636 minimum
        XCTAssertLessThanOrEqual(v.count, 128)
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_")
        XCTAssertTrue(v.unicodeScalars.allSatisfy(allowed.contains))
        XCTAssertNotEqual(GoogleHealthAuth.makeCodeVerifier(), v)   // random each time
    }

    func testReversedClientIDAndRedirect() {
        let id = "1234567-abc123.apps.googleusercontent.com"
        XCTAssertEqual(GoogleHealthAuth.reversedClientID(id),
                       "com.googleusercontent.apps.1234567-abc123")
        XCTAssertEqual(GoogleHealthAuth.redirectURI(for: id),
                       "com.googleusercontent.apps.1234567-abc123:/oauthredirect")
    }

    func testAuthorizationURLCarriesPKCEAndScopes() throws {
        let id = "1234567-abc123.apps.googleusercontent.com"
        let url = try XCTUnwrap(GoogleHealthAuth.authorizationURL(clientID: id, challenge: "CHAL"))
        let comps = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        XCTAssertEqual(comps.host, "accounts.google.com")
        let items = Dictionary(uniqueKeysWithValues: (comps.queryItems ?? []).map { ($0.name, $0.value ?? "") })
        XCTAssertEqual(items["client_id"], id)
        XCTAssertEqual(items["response_type"], "code")
        XCTAssertEqual(items["code_challenge"], "CHAL")
        XCTAssertEqual(items["code_challenge_method"], "S256")
        XCTAssertEqual(items["redirect_uri"], GoogleHealthAuth.redirectURI(for: id))
        for scope in GoogleHealthAuth.scopes {
            XCTAssertTrue(items["scope"]?.contains(scope) == true, "missing scope \(scope)")
        }
    }

    // MARK: - Small helpers

    func testDurationAndTimestampHelpers() {
        XCTAssertEqual(GoogleHealthClient.durationSeconds("3600s"), 3600)
        XCTAssertEqual(GoogleHealthClient.durationSeconds("3600.5s"), 3600.5)
        XCTAssertNil(GoogleHealthClient.durationSeconds(nil))
        XCTAssertNotNil(GoogleHealthClient.rfc3339("2026-07-09T17:00:00Z"))
        XCTAssertNotNil(GoogleHealthClient.rfc3339("2026-07-09T17:00:00.123Z"))
        XCTAssertNil(GoogleHealthClient.rfc3339("not a date"))
    }

    func testCivilDateStringForFilterLiterals() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        let now = ISO8601DateFormatter().date(from: "2026-07-10T19:00:00Z")!  // July 10, noon PT
        XCTAssertEqual(GoogleHealthClient.civilDateString(daysAgo: 14, from: now, calendar: cal),
                       "2026-06-26")
    }
}
